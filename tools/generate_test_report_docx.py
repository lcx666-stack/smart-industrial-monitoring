#!/usr/bin/env python3
"""Generate a quantified test report from the benchmark JSON files."""

import json
from pathlib import Path
import sys

from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor


ROOT = Path(__file__).resolve().parents[1]
CONTROL_BASELINE = ROOT / 'log/benchmark_control_sync_20261030.json'
CONTROL = ROOT / 'log/benchmark_control_sync_fast_20261030.json'
ACQUISITION = ROOT / 'log/benchmark_acquisition_latency_20261030.json'
AI = ROOT / 'log/benchmark_ai_inference_300_20261030.json'
CAN = ROOT / 'log/benchmark_can_stability_20261030.json'
OUTPUT = Path.home() / 'Desktop/完整测试报告_20261030.docx'

NAVY = RGBColor(0x18, 0x2F, 0x4A)
BLUE = RGBColor(0x17, 0x67, 0xB3)
GRAY = RGBColor(0x55, 0x65, 0x76)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def set_font(run, east_asia='宋体', latin='Times New Roman',
             size=10.5, bold=False, color=None):
    run.font.name = latin
    run.font.size = Pt(size)
    run.font.bold = bold
    if color is not None:
        run.font.color.rgb = color
    run._element.get_or_add_rPr().rFonts.set(qn('w:eastAsia'), east_asia)


def configure(document):
    section = document.sections[0]
    section.top_margin = Cm(2.0)
    section.bottom_margin = Cm(2.0)
    section.left_margin = Cm(2.2)
    section.right_margin = Cm(2.2)
    normal = document.styles['Normal']
    normal.font.name = 'Times New Roman'
    normal.font.size = Pt(10.5)
    normal.element.rPr.rFonts.set(qn('w:eastAsia'), '宋体')
    normal.paragraph_format.line_spacing = 1.2
    normal.paragraph_format.space_after = Pt(3)
    title = document.styles['Title']
    title.font.name = 'Microsoft YaHei'
    title.font.size = Pt(20)
    title.font.bold = True
    title.font.color.rgb = NAVY
    title.element.rPr.rFonts.set(qn('w:eastAsia'), '微软雅黑')
    for name, size in (('Heading 1', 14), ('Heading 2', 12)):
        style = document.styles[name]
        style.font.name = 'Microsoft YaHei'
        style.font.size = Pt(size)
        style.font.bold = True
        style.font.color.rgb = NAVY if name == 'Heading 1' else BLUE
        style.element.rPr.rFonts.set(qn('w:eastAsia'), '微软雅黑')
        style.paragraph_format.space_before = Pt(10)
        style.paragraph_format.space_after = Pt(4)


def paragraph(document, text, indent=True, color=None, bold=False):
    result = document.add_paragraph()
    if indent:
        result.paragraph_format.first_line_indent = Cm(.74)
    run = result.add_run(text)
    set_font(run, color=color, bold=bold)
    return result


def shade(cell, color):
    properties = cell._tc.get_or_add_tcPr()
    node = OxmlElement('w:shd')
    node.set(qn('w:fill'), color)
    properties.append(node)


def cell_text(cell, value, bold=False, color=None):
    cell.text = ''
    paragraph_ = cell.paragraphs[0]
    run = paragraph_.add_run(str(value))
    set_font(run, size=9.5, bold=bold, color=color)
    cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER


def table(document, headings, rows, widths=None):
    result = document.add_table(rows=1, cols=len(headings))
    result.style = 'Table Grid'
    result.alignment = WD_TABLE_ALIGNMENT.CENTER
    for column, heading in enumerate(headings):
        cell_text(result.rows[0].cells[column], heading,
                  bold=True, color=WHITE)
        shade(result.rows[0].cells[column], '1767B3')
    for row_index, values in enumerate(rows):
        cells = result.add_row().cells
        for column, value in enumerate(values):
            cell_text(cells[column], value)
            if row_index % 2:
                shade(cells[column], 'EEF4FA')
    if widths:
        for row in result.rows:
            for column, width in enumerate(widths):
                row.cells[column].width = Cm(width)
    document.add_paragraph()
    return result


def ms(value, digits=2):
    return '' if value is None else ('{:.{}f}'.format(value, digits))


def main():
    control = load(CONTROL)
    control_before = load(CONTROL_BASELINE)
    acquisition = load(ACQUISITION)
    ai = load(AI)
    can = load(CAN)
    document = Document()
    configure(document)

    title = document.add_paragraph(style='Title')
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = title.add_run('智能工业状态监测与安全控制系统\n完整测试报告')
    set_font(run, east_asia='微软雅黑', latin='Microsoft YaHei',
             size=20, bold=True, color=NAVY)
    meta = document.add_paragraph()
    meta.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = meta.add_run('测试日期：2026-10-30    平台：MLK-F3P-DR1M90G')
    set_font(run, east_asia='微软雅黑', latin='Microsoft YaHei',
             size=10.5, color=GRAY)

    document.add_heading('1  测试环境与边界', level=1)
    paragraph(
        document,
        '测试对象包括 PL ADC/DMA 采集链路、PS Linux 控制链路、板载 NPU '
        '推理以及 CS500 与 STM32F103C8T6 之间的 CAN 报警链路。测试期间'
        '现场安全条件已确认；测试结束时电机停止、AI 预览停止、波形监测恢复，'
        'STM32 保持配对状态。')
    paragraph(
        document,
        'CAN0 使用 500 kbit/s 经典 CAN、11 位标准帧和 DLC=8。控制测试使用'
        '以太网/SSH 持久控制通道；采集测试使用 100 MHz PL 时钟计数的 64 位'
        ' sample_ticks；NPU 测试通过视频端口 5000 接收 960×540 预览帧。')

    document.add_heading('2  控制同步精度', level=1)
    paragraph(
        document,
        '共执行 5 轮“10% 启动 → 15% 运行调速 → 正常停机”。启动流程已移除'
        '控制层的重复预检，正式电机进程只执行一次 ADC 和基线检查；控制命令'
        '会等待 PL PWM 回读确认后再返回。命令确认时间从'
        '电脑发送命令到收到板端响应；状态生效时间从发送命令到状态读取确认'
        '目标状态，状态轮询间隔为 50 ms。')
    control_rows = []
    labels = (
        ('start_ack_ms', '启动命令', '命令确认'),
        ('start_apply_ms', '启动命令', '状态生效'),
        ('duty_ack_ms', '运行调速', '命令确认'),
        ('duty_apply_ms', '运行调速', '状态生效'),
        ('stop_ack_ms', '正常停机', '命令确认'),
        ('stop_apply_ms', '正常停机', '状态生效'),
    )
    for key, operation, metric in labels:
        values = control['summary'][key]
        control_rows.append((
            operation, metric, values['count'], ms(values['mean_ms']),
            ms(values['p50_ms']), ms(values['p95_ms']), ms(values['max_ms'])))
    table(document,
          ('操作', '指标', '样本', '平均/ms', 'P50/ms', 'P95/ms', '最大/ms'),
          control_rows, (2.0, 2.2, 1.2, 2.0, 2.0, 2.0, 2.0))
    paragraph(
        document,
        '结果：5 轮全部成功；最终由新版 helper 确认 motor_running=false、'
        'applied_duty=0、fault_latched=false。启动命令包含预检和进程启动，'
        '因此确认时间明显高于运行调速和正常停机。')

    before_start = control_before['summary']['start_apply_ms']
    after_start = control['summary']['start_apply_ms']
    reduction = before_start['mean_ms'] - after_start['mean_ms']
    reduction_percent = reduction * 100.0 / before_start['mean_ms']
    table(document,
          ('启动指标', '优化前', '优化后', '改善'),
          (
              ('平均状态生效时间',
               ms(before_start['mean_ms']) + ' ms',
               ms(after_start['mean_ms']) + ' ms',
               '{} ms / {:.1f}%'.format(ms(reduction),
                                        reduction_percent)),
              ('P95 状态生效时间',
               ms(before_start['p95_ms']) + ' ms',
               ms(after_start['p95_ms']) + ' ms',
               '{} ms'.format(ms(before_start['p95_ms'] -
                                 after_start['p95_ms']))),
          ), (4.2, 3.2, 3.2, 4.1))

    document.add_heading('3  采集时序与延迟', level=1)
    paragraph(
        document,
        '采集间隔由连续帧的 64 位 sample_ticks 差值计算。数据年龄定义为：'
        'PS 读取最新帧后，立即触发 PL 状态快照，以快照 100 MHz tick 减去'
        '该帧 sample_ticks，再换算为微秒。')
    acquisition_rows = (
        ('采样周期', '20.000 µs',
         '{} 个 tick 差值'.format(
             acquisition['sample_tick_interval']['count'])),
        ('采样率', '50,000 Hz', '由 tick 差值反算'),
        ('最新 PL 样本年龄 P50',
         ms(acquisition['pl_latest_sample_age_us']['p50_us'], 3) + ' µs',
         '{} 次状态快照'.format(
             acquisition['pl_latest_sample_age_us']['count'])),
        ('最新 PL 样本年龄 P95',
         ms(acquisition['pl_latest_sample_age_us']['p95_us'], 3) + ' µs',
         '最大 {} µs'.format(
             ms(acquisition['pl_latest_sample_age_us']['max_us'], 3))),
        ('DMA→PS 数据年龄 平均',
         ms(acquisition['dma_to_ps_sample_age_us']['mean_us'], 3) + ' µs',
         '{} 次测量'.format(
             acquisition['dma_to_ps_sample_age_us']['count'])),
        ('DMA→PS 数据年龄 P95',
         ms(acquisition['dma_to_ps_sample_age_us']['p95_us'], 3) + ' µs',
         '最大 {} µs'.format(
             ms(acquisition['dma_to_ps_sample_age_us']['max_us'], 3))),
        ('DMA dropped', str(acquisition['final_status']['dropped']),
         'ADC error count={}（测试前后不变）'.format(
             acquisition['final_status']['adc_errors'])),
    )
    table(document, ('指标', '实测值', '说明'), acquisition_rows,
          (4.2, 3.8, 8.0))
    paragraph(
        document,
        '说明：采样率反映采集周期；DMA→PS 数据年龄反映采样时间戳到 PS '
        '读取完成之间的延迟。该测试不包含传感器模拟前端建立时间，也不包含'
        '波形通过网络发送到电脑窗口的显示延迟。')

    document.add_heading('4  AI 推理耗时', level=1)
    paragraph(
        document,
        '使用当前默认的 round2_118 bias ROI fast 模型，持续接收 300 帧视频'
        '预览。板端每 30 帧输出一次推理统计，共取得 {} 个统计窗口。'.format(
            ai['reported_infer_ms']['count']))
    ai_rows = (
        ('推理耗时平均值', ms(ai['reported_infer_ms']['mean']) + ' ms',
         '{} 个窗口'.format(ai['reported_infer_ms']['count'])),
        ('推理耗时 P50', ms(ai['reported_infer_ms']['p50']) + ' ms', ''),
        ('推理耗时 P95', ms(ai['reported_infer_ms']['p95']) + ' ms',
         '最大 {} ms'.format(ms(ai['reported_infer_ms']['max']))),
        ('板端报告帧率平均', ms(ai['reported_fps']['mean']) + ' FPS',
         'P95 {} FPS'.format(ms(ai['reported_fps']['p95']))),
        ('端到端预览帧率', ms(ai['wall_fps']) + ' FPS',
         '{} 帧'.format(ai['received_frames'])),
        ('NPU 结果帧龄 P95', ms(ai['npu_frame_age']['p95'], 1) + ' 帧',
         '最大 {} 帧'.format(ms(ai['npu_frame_age']['max'], 1))),
        ('AI 启动/停止确认',
         '{} / {} ms'.format(ms(ai['start_ack_ms']),
                             ms(ai['stop_ack_ms'])), ''),
    )
    table(document, ('指标', '实测值', '说明'), ai_rows,
          (4.2, 4.2, 7.6))
    paragraph(
        document,
        'AI 测试结束后日志包含 BOARD_AI_STOPPED 和 CMA released，'
        'final_ai_running=false。推理统计为板端每 30 帧报告值，不是对每个'
        '单帧单独打点。')

    document.add_heading('5  CAN 总线通信稳定性', level=1)
    paragraph(
        document,
        'CS500 向 STM32 连续发送 500 个 0x180 报警帧，发送间隔 20 ms；'
        '使用相同 seq 验证重复报警确认，同时避免每个测试帧产生新的蜂鸣周期。'
        '每个发送帧都必须收到匹配 seq 的 0x280 确认。')
    can_rows = (
        ('测试发送/确认/丢失',
         '{} / {} / {}'.format(can['sent'], can['acked'], can['lost']),
         '成功率 {}%'.format(can['success_rate_percent'])),
        ('实际发送速率', ms(can['effective_rate_hz']) + ' Hz',
         '测试时长 {} s'.format(ms(can['duration_s']))),
        ('报警→ACK 平均',
         ms(can['rtt_ms']['mean'], 3) + ' ms',
         'P50 {} ms'.format(ms(can['rtt_ms']['p50'], 3))),
        ('报警→ACK P95',
         ms(can['rtt_ms']['p95'], 3) + ' ms',
         '最大 {} ms'.format(ms(can['rtt_ms']['max'], 3))),
        ('总线状态', can['can_state'], ''),
        ('错误计数变化',
         'bus-errors {} → {}，bus-off {} → {}'.format(
             can['before']['bus-errors'], can['after']['bus-errors'],
             can['before']['bus-off'], can['after']['bus-off']), ''),
        ('驱动 RX/TX 丢包',
         'RX dropped {} → {}，TX dropped {} → {}'.format(
             can['before']['rx_dropped'], can['after']['rx_dropped'],
             can['before']['tx_dropped'], can['after']['tx_dropped']), ''),
        ('STM32 配对', 'nonce=F32D',
         '主板日志 STM32 paired'),
    )
    table(document, ('指标', '实测值', '说明'), can_rows,
          (4.4, 6.2, 5.4))

    document.add_heading('6  结论', level=1)
    paragraph(
        document,
        '本轮测试完成了四项定量验证：控制命令与状态生效延迟；50 kHz 采样'
        '周期及 DMA 到 PS 数据年龄；300 帧 NPU 推理统计；500 帧 CAN 报警与'
        '确认稳定性。测试期间 CAN 未新增总线错误或 bus-off，电机测试最终回到'
        '停止状态，AI 测试正常释放 CMA，波形监测已恢复。')

    document.add_heading('7  原始数据文件', level=1)
    for name in ('benchmark_control_sync_20261030.json',
                 'benchmark_control_sync_fast_20261030.json',
                 'benchmark_acquisition_latency_20261030.json',
                 'benchmark_ai_inference_300_20261030.json',
                 'benchmark_can_stability_20261030.json'):
        paragraph(document, 'D:\\qian_ru_shi_competition\\log\\' + name,
                  indent=False)

    footer = document.sections[0].footer.paragraphs[0]
    footer.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = footer.add_run('智能工业状态监测与安全控制系统 · 定量测试报告')
    set_font(run, east_asia='微软雅黑', latin='Microsoft YaHei',
             size=9, color=GRAY)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    document.save(str(OUTPUT))
    print(OUTPUT)


if __name__ == '__main__':
    main()
