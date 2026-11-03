// SPDX-License-Identifier: GPL-2.0
// PS-side coherent DDR ring for the PL HP0 waveform writer.
#include <linux/bitops.h>
#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/fs.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/uaccess.h>

#include "motor_wave_dma_uapi.h"

#define REG_STATUS_ID       0x00
#define REG_FEATURES        0x54
#define REG_LIVE_FLAGS      0x48
#define REG_ADC_ERRORS      0x5c
#define REG_DMA_ID          0x80
#define REG_DMA_ABI         0x84
#define REG_DMA_CONTROL     0x88
#define REG_DMA_BASE_LO     0x8c
#define REG_DMA_BASE_HI     0x90
#define REG_DMA_SIZE        0x94
#define REG_DMA_CONSUMED    0x98
#define REG_DMA_PRODUCED    0x9c
#define REG_DMA_DROPPED     0xa0
#define REG_DMA_SEQ         0xa4
#define REG_DMA_FLAGS       0xa8
#define REG_DMA_FIFO        0xac

#define FRAME_BYTES         32U
#define DMA_FEATURE         BIT(6)
#define DMA_ACTIVE          BIT(0)
#define DMA_BUSY            BIT(1)
#define DMA_ERROR           BIT(3)

static unsigned int buffer_mib = 8;
module_param(buffer_mib, uint, 0444);
MODULE_PARM_DESC(buffer_mib, "Coherent waveform ring size in MiB (1..64)");

struct motor_wave_dev {
    struct device *dev;
    void __iomem *regs;
    void *cpu_buffer;
    dma_addr_t dma_handle;
    size_t buffer_size;
    u32 consumed;
    bool opened;
    struct mutex lock;
    struct miscdevice misc;
};

static inline u32 wave_read(struct motor_wave_dev *wave, u32 offset)
{
    return readl(wave->regs + offset);
}

static inline void wave_write(struct motor_wave_dev *wave, u32 offset, u32 value)
{
    writel(value, wave->regs + offset);
}

static int motor_wave_open(struct inode *inode, struct file *file)
{
    struct miscdevice *misc = file->private_data;
    struct motor_wave_dev *wave = container_of(misc, struct motor_wave_dev,
                                               misc);

    mutex_lock(&wave->lock);
    if (wave->opened) {
        mutex_unlock(&wave->lock);
        return -EBUSY;
    }
    wave->opened = true;
    file->private_data = wave;
    mutex_unlock(&wave->lock);
    return nonseekable_open(inode, file);
}

static int motor_wave_release(struct inode *inode, struct file *file)
{
    struct motor_wave_dev *wave = file->private_data;

    mutex_lock(&wave->lock);
    // A killed userspace recorder must not leave the PL filling this ring.
    wave_write(wave, REG_DMA_CONTROL, 2);
    wave->consumed = wave_read(wave, REG_DMA_PRODUCED);
    wave_write(wave, REG_DMA_CONSUMED, wave->consumed);
    (void)wave_read(wave, REG_DMA_FLAGS);
    wave->opened = false;
    mutex_unlock(&wave->lock);
    return 0;
}

static long motor_wave_ioctl(struct file *file, unsigned int command,
                             unsigned long argument)
{
    struct motor_wave_dev *wave = file->private_data;
    struct motor_wave_status status;
    u32 flags;
    unsigned int attempt;
    long result = 0;

    mutex_lock(&wave->lock);
    switch (command) {
    case MOTOR_WAVE_IOC_START:
        flags = wave_read(wave, REG_DMA_FLAGS);
        if (flags & (DMA_ACTIVE | DMA_BUSY)) {
            result = -EBUSY;
            break;
        }
        wave->consumed = 0;
        wave_write(wave, REG_DMA_BASE_LO, lower_32_bits(wave->dma_handle));
        wave_write(wave, REG_DMA_BASE_HI, upper_32_bits(wave->dma_handle));
        wave_write(wave, REG_DMA_SIZE, wave->buffer_size);
        wave_write(wave, REG_DMA_CONSUMED, 0);
        wave_write(wave, REG_DMA_CONTROL, 1);
        (void)wave_read(wave, REG_DMA_CONTROL); // flush ordered MMIO writes
        for (attempt = 0; attempt < 100; attempt++) {
            flags = wave_read(wave, REG_DMA_FLAGS);
            if (flags & (DMA_ACTIVE | DMA_ERROR))
                break;
            udelay(10);
        }
        if (flags & DMA_ERROR)
            result = -EIO;
        else if (!(flags & DMA_ACTIVE))
            result = -ETIMEDOUT;
        break;
    case MOTOR_WAVE_IOC_STOP:
        wave_write(wave, REG_DMA_CONTROL, 2);
        (void)wave_read(wave, REG_DMA_CONTROL);
        break;
    case MOTOR_WAVE_IOC_STATUS:
        status.produced_bytes = wave_read(wave, REG_DMA_PRODUCED);
        status.consumed_bytes = wave->consumed;
        status.dropped_frames = wave_read(wave, REG_DMA_DROPPED);
        status.frame_seq = wave_read(wave, REG_DMA_SEQ);
        status.flags = wave_read(wave, REG_DMA_FLAGS);
        status.fifo_used = wave_read(wave, REG_DMA_FIFO);
        status.buffer_bytes = wave->buffer_size;
        status.live_flags = wave_read(wave, REG_LIVE_FLAGS);
        status.adc_error_count = wave_read(wave, REG_ADC_ERRORS);
        status.reserved = 0;
        if (copy_to_user((void __user *)argument, &status,
                         sizeof(status)))
            result = -EFAULT;
        break;
    default:
        result = -ENOTTY;
        break;
    }
    mutex_unlock(&wave->lock);
    return result;
}

static ssize_t motor_wave_read(struct file *file, char __user *buffer,
                               size_t requested, loff_t *position)
{
    struct motor_wave_dev *wave = file->private_data;
    u32 produced, available, offset;
    size_t count, first;
    u32 flags;

    if (requested < FRAME_BYTES || requested % FRAME_BYTES)
        return -EINVAL;
    if (requested > wave->buffer_size)
        requested = wave->buffer_size;

    for (;;) {
        mutex_lock(&wave->lock);
        produced = wave_read(wave, REG_DMA_PRODUCED);
        available = produced - wave->consumed;
        if (available > wave->buffer_size) {
            mutex_unlock(&wave->lock);
            return -EIO;
        }
        if (available) break;
        flags = wave_read(wave, REG_DMA_FLAGS);
        mutex_unlock(&wave->lock);
        if ((flags & DMA_ERROR) || !(flags & (DMA_ACTIVE | DMA_BUSY)))
            return 0;
        if (file->f_flags & O_NONBLOCK)
            return -EAGAIN;
        if (msleep_interruptible(2))
            return -ERESTARTSYS;
    }

    count = min_t(size_t, requested, available);
    count -= count % FRAME_BYTES;
    offset = wave->consumed % wave->buffer_size;
    first = min_t(size_t, count, wave->buffer_size - offset);
    dma_rmb(); // observe PL writes before copying B-committed frames
    if (copy_to_user(buffer, (char *)wave->cpu_buffer + offset, first) ||
        (count > first &&
         copy_to_user(buffer + first, wave->cpu_buffer, count - first))) {
        mutex_unlock(&wave->lock);
        return -EFAULT;
    }
    wave->consumed += count;
    wave_write(wave, REG_DMA_CONSUMED, wave->consumed);
    mutex_unlock(&wave->lock);
    return count;
}

static const struct file_operations motor_wave_fops = {
    .owner = THIS_MODULE,
    .open = motor_wave_open,
    .release = motor_wave_release,
    .unlocked_ioctl = motor_wave_ioctl,
    .read = motor_wave_read,
    .llseek = no_llseek,
};

static int motor_wave_probe(struct platform_device *pdev)
{
    struct motor_wave_dev *wave;
    struct resource *resource;
    int error;

    if (buffer_mib < 1 || buffer_mib > 64)
        return -EINVAL;
    wave = devm_kzalloc(&pdev->dev, sizeof(*wave), GFP_KERNEL);
    if (!wave)
        return -ENOMEM;
    wave->dev = &pdev->dev;
    wave->buffer_size = (size_t)buffer_mib * 1024 * 1024;
    mutex_init(&wave->lock);
    resource = platform_get_resource(pdev, IORESOURCE_MEM, 0);
    if (!resource)
        return -ENODEV;
    wave->regs = devm_ioremap_resource(&pdev->dev, resource);
    if (IS_ERR(wave->regs))
        return PTR_ERR(wave->regs);
    if (wave_read(wave, REG_STATUS_ID) != 0x4d535431 ||
        wave_read(wave, REG_DMA_ID) != 0x444d4131 ||
        wave_read(wave, REG_DMA_ABI) != 0x00010000 ||
        !(wave_read(wave, REG_FEATURES) & DMA_FEATURE))
        return -ENODEV;
    error = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(33));
    if (error)
        error = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(32));
    if (error)
        return error;
    wave->cpu_buffer = dma_alloc_coherent(&pdev->dev, wave->buffer_size,
                                          &wave->dma_handle, GFP_KERNEL);
    if (!wave->cpu_buffer)
        return -ENOMEM;
    if (((u64)wave->dma_handle >> 33) != 0) {
        error = -ERANGE;
        goto free_buffer;
    }
    wave->misc.minor = MISC_DYNAMIC_MINOR;
    wave->misc.name = "motor_wave_dma";
    wave->misc.fops = &motor_wave_fops;
    wave->misc.parent = &pdev->dev;
    error = misc_register(&wave->misc);
    if (error)
        goto free_buffer;
    platform_set_drvdata(pdev, wave);
    dev_info(&pdev->dev, "waveform ring: %zu bytes, DMA %pad\n",
             wave->buffer_size, &wave->dma_handle);
    return 0;

free_buffer:
    dma_free_coherent(&pdev->dev, wave->buffer_size, wave->cpu_buffer,
                      wave->dma_handle);
    return error;
}

static int motor_wave_remove(struct platform_device *pdev)
{
    struct motor_wave_dev *wave = platform_get_drvdata(pdev);
    unsigned int attempt;

    misc_deregister(&wave->misc);
    wave_write(wave, REG_DMA_CONTROL, 2);
    for (attempt = 0; attempt < 1000; attempt++) {
        if (!(wave_read(wave, REG_DMA_FLAGS) & (DMA_ACTIVE | DMA_BUSY)))
            break;
        // Drain the bounded PL FIFO before releasing the DDR destination.
        wave_write(wave, REG_DMA_CONSUMED,
                   wave_read(wave, REG_DMA_PRODUCED));
        usleep_range(1000, 2000);
    }
    if (attempt == 1000) {
        dev_err(&pdev->dev, "HP0 did not quiesce; retaining DMA buffer until reboot\n");
        return 0;
    }
    dma_free_coherent(&pdev->dev, wave->buffer_size, wave->cpu_buffer,
                      wave->dma_handle);
    return 0;
}

static const struct of_device_id motor_wave_match[] = {
    { .compatible = "qrs,motor-wave-dma" },
    { }
};
MODULE_DEVICE_TABLE(of, motor_wave_match);

static struct platform_driver motor_wave_driver = {
    .probe = motor_wave_probe,
    .remove = motor_wave_remove,
    .driver = {
        .name = "motor-wave-dma",
        .of_match_table = motor_wave_match,
    },
};
module_platform_driver(motor_wave_driver);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Coherent AD7606 waveform DMA ring for the QRS SoC project");
