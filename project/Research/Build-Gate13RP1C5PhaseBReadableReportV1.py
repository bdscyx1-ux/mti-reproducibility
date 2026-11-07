#!/usr/bin/env python3
"""Build a readable Chinese DOCX report from the frozen Gate 13R P1-C5 Phase B outputs."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from docx import Document
from docx.enum.section import WD_ORIENT
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


PROJECT = Path(r"H:\DDM_Final_Project")
RESULT_PATH = PROJECT / "Research/Analysis/Gate13R_P1C5_Independent/v1/confirmatory-p1-c5-result.json"
RAW_COMMIT_PATH = PROJECT / "Research/FormalRuns/Gate13R_P1C5_Independent/v1/raw-data-complete.json"
AUTH_PATH = PROJECT / "Research/Gate13R_P1C5_Independent_PhaseB_Authorization.v1.json"
OUTPUT_DIR = PROJECT / "Research/Reports/Gate13R_P1C5_Independent/v1"
OUTPUT_PATH = OUTPUT_DIR / "Gate13R_P1C5_PhaseB_Results_Readable_Report.zh-CN.docx"
BUILD_DIR = PROJECT / ".codex_tmp/gate13r_p1c5_phaseb_readable_report"
FIGURE_PATH = BUILD_DIR / "p1_ratio_ci.png"

FONT_CN = "Microsoft YaHei"
FONT_MONO = "Consolas"
NAVY = "1F4E79"
PALE_BLUE = "EAF2F8"
MID_BLUE = "5B9BD5"
GRAY = "666666"
LIGHT_GRAY = "D9D9D9"
PALE_GRAY = "F6F7F8"
BLACK = "000000"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def set_run_font(run, name=FONT_CN, size=10.5, bold=None, color=BLACK, italic=None):
    run.font.name = name
    run._element.get_or_add_rPr().get_or_add_rFonts().set(qn("w:eastAsia"), name)
    run._element.get_or_add_rPr().get_or_add_rFonts().set(qn("w:ascii"), name)
    run._element.get_or_add_rPr().get_or_add_rFonts().set(qn("w:hAnsi"), name)
    run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if italic is not None:
        run.italic = italic
    run.font.color.rgb = RGBColor.from_string(color)


def set_cell_shading(cell, fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), fill)


def set_cell_margins(cell, top=90, start=120, bottom=90, end=120):
    tc = cell._tc
    tc_pr = tc.get_or_add_tcPr()
    tc_mar = tc_pr.first_child_found_in("w:tcMar")
    if tc_mar is None:
        tc_mar = OxmlElement("w:tcMar")
        tc_pr.append(tc_mar)
    for margin, value in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        node = tc_mar.find(qn(f"w:{margin}"))
        if node is None:
            node = OxmlElement(f"w:{margin}")
            tc_mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")


def set_table_borders(table, color=LIGHT_GRAY, size="6"):
    tbl_pr = table._tbl.tblPr
    borders = tbl_pr.first_child_found_in("w:tblBorders")
    if borders is None:
        borders = OxmlElement("w:tblBorders")
        tbl_pr.append(borders)
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        node = borders.find(qn(f"w:{edge}"))
        if node is None:
            node = OxmlElement(f"w:{edge}")
            borders.append(node)
        node.set(qn("w:val"), "single")
        node.set(qn("w:sz"), size)
        node.set(qn("w:space"), "0")
        node.set(qn("w:color"), color)


def set_repeat_header(row):
    tr_pr = row._tr.get_or_add_trPr()
    tbl_header = OxmlElement("w:tblHeader")
    tbl_header.set(qn("w:val"), "true")
    tr_pr.append(tbl_header)


def prevent_row_split(row):
    tr_pr = row._tr.get_or_add_trPr()
    cant_split = OxmlElement("w:cantSplit")
    tr_pr.append(cant_split)


def set_cell_text(cell, text, *, bold=False, color=BLACK, size=9.5, align=WD_ALIGN_PARAGRAPH.LEFT, mono=False):
    cell.text = ""
    paragraph = cell.paragraphs[0]
    paragraph.alignment = align
    paragraph.paragraph_format.space_after = Pt(0)
    paragraph.paragraph_format.space_before = Pt(0)
    paragraph.paragraph_format.line_spacing = 1.08
    run = paragraph.add_run(str(text))
    set_run_font(run, FONT_MONO if mono else FONT_CN, size, bold, color)
    cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    set_cell_margins(cell)


def set_col_width(cell, width_inches):
    tc_pr = cell._tc.get_or_add_tcPr()
    tc_w = tc_pr.find(qn("w:tcW"))
    if tc_w is None:
        tc_w = OxmlElement("w:tcW")
        tc_pr.append(tc_w)
    tc_w.set(qn("w:w"), str(int(width_inches * 1440)))
    tc_w.set(qn("w:type"), "dxa")


def style_table(table, widths, header=True, small=False):
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    set_table_borders(table)
    if header:
        set_repeat_header(table.rows[0])
    for r_idx, row in enumerate(table.rows):
        prevent_row_split(row)
        for c_idx, cell in enumerate(row.cells):
            set_col_width(cell, widths[c_idx])
            if r_idx == 0 and header:
                set_cell_shading(cell, NAVY)
                for p in cell.paragraphs:
                    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    for run in p.runs:
                        set_run_font(run, FONT_CN, 9.0 if small else 9.5, True, "FFFFFF")
            elif r_idx % 2 == 0:
                set_cell_shading(cell, PALE_BLUE)


def add_paragraph(doc, text="", *, bold_lead=None, style=None, align=None, size=10.5, color=BLACK, space_after=6):
    paragraph = doc.add_paragraph(style=style)
    if align is not None:
        paragraph.alignment = align
    paragraph.paragraph_format.space_after = Pt(space_after)
    paragraph.paragraph_format.line_spacing = 1.28
    if bold_lead and text.startswith(bold_lead):
        lead = paragraph.add_run(bold_lead)
        set_run_font(lead, FONT_CN, size, True, color)
        body = paragraph.add_run(text[len(bold_lead):])
        set_run_font(body, FONT_CN, size, False, color)
    else:
        run = paragraph.add_run(text)
        set_run_font(run, FONT_CN, size, False, color)
    return paragraph


def add_bullet(doc, text, *, level=0):
    paragraph = doc.add_paragraph(style="List Bullet" if level == 0 else "List Bullet 2")
    paragraph.paragraph_format.space_after = Pt(3.5)
    paragraph.paragraph_format.line_spacing = 1.2
    run = paragraph.add_run(text)
    set_run_font(run, FONT_CN, 10.2, False, BLACK)
    return paragraph


def add_heading(doc, text, level=1):
    paragraph = doc.add_heading(text, level=level)
    paragraph.paragraph_format.keep_with_next = True
    paragraph.paragraph_format.space_before = Pt(11 if level == 1 else 8)
    paragraph.paragraph_format.space_after = Pt(5)
    for run in paragraph.runs:
        set_run_font(run, FONT_CN, 15 if level == 1 else 12.5, True, BLACK)
    return paragraph


def add_caption(doc, text):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after = Pt(7)
    run = p.add_run(text)
    set_run_font(run, FONT_CN, 9, False, GRAY)
    return p


def set_picture_alt_text(inline_shape, title, description):
    doc_pr = inline_shape._inline.docPr
    doc_pr.set("title", title)
    doc_pr.set("descr", description)


def remove_paragraph_borders(paragraph_or_style):
    element = paragraph_or_style._element
    p_pr = element.get_or_add_pPr()
    p_bdr = p_pr.find(qn("w:pBdr"))
    if p_bdr is not None:
        p_pr.remove(p_bdr)


def make_ratio_figure(ratio, lower, upper):
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    width, height = 1600, 650
    img = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(img)
    regular = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 38)
    small = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 29)
    tiny = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 24)
    bold = ImageFont.truetype(r"C:\Windows\Fonts\msyhbd.ttc", 45)

    draw.text((80, 42), "IDFF 与 C-FF 的 P1 几何均值比", font=bold, fill=(31, 78, 121))
    draw.text((80, 105), "比值小于 1 表示 IDFF 的 P1 更低", font=small, fill=(85, 85, 85))

    x_min, x_max = 0.76, 1.02
    axis_left, axis_right = 150, 1450
    axis_y = 390

    def xpos(value):
        return axis_left + (value - x_min) / (x_max - x_min) * (axis_right - axis_left)

    draw.line((axis_left, axis_y, axis_right, axis_y), fill=(80, 80, 80), width=3)
    ticks = [0.76, 0.80, 0.84, 0.88, 0.92, 0.96, 1.00]
    for tick in ticks:
        x = xpos(tick)
        draw.line((x, axis_y - 10, x, axis_y + 10), fill=(80, 80, 80), width=2)
        label = f"{tick:.2f}"
        box = draw.textbbox((0, 0), label, font=tiny)
        draw.text((x - (box[2] - box[0]) / 2, axis_y + 20), label, font=tiny, fill=(70, 70, 70))

    null_x = xpos(1.0)
    y = 175
    while y < axis_y + 2:
        draw.line((null_x, y, null_x, min(y + 18, axis_y + 2)), fill=(170, 60, 60), width=3)
        y += 30
    draw.text((null_x - 68, 138), "无差异 1.00", font=tiny, fill=(150, 50, 50))

    ci_y = 300
    low_x, high_x, est_x = xpos(lower), xpos(upper), xpos(ratio)
    draw.line((low_x, ci_y, high_x, ci_y), fill=(31, 78, 121), width=12)
    draw.line((low_x, ci_y - 23, low_x, ci_y + 23), fill=(31, 78, 121), width=7)
    draw.line((high_x, ci_y - 23, high_x, ci_y + 23), fill=(31, 78, 121), width=7)
    diamond = [(est_x, ci_y - 24), (est_x + 24, ci_y), (est_x, ci_y + 24), (est_x - 24, ci_y)]
    draw.polygon(diamond, fill=(91, 155, 213), outline=(31, 78, 121))

    result_text = f"估计值 {ratio:.4f}    95% CI [{lower:.4f}, {upper:.4f}]"
    box = draw.textbbox((0, 0), result_text, font=regular)
    draw.text(((width - (box[2] - box[0])) / 2, 215), result_text, font=regular, fill=(31, 78, 121))

    draw.text((axis_left, 515), "IDFF 的 P1 更低", font=small, fill=(31, 78, 121))
    right_text = "C-FF 的 P1 更低"
    box = draw.textbbox((0, 0), right_text, font=small)
    draw.text((axis_right - (box[2] - box[0]), 515), right_text, font=small, fill=(110, 110, 110))
    draw.text((80, 588), "点表示几何均值比，横线表示双侧 95% t 置信区间。", font=tiny, fill=(95, 95, 95))

    img.save(FIGURE_PATH, format="PNG", dpi=(300, 300))


def add_footer(section):
    footer = section.footer
    table = footer.add_table(rows=1, cols=2, width=Inches(6.8))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    left, right = table.rows[0].cells
    set_cell_text(left, "Gate 13R P1-C5 Independent v1", size=8.3, color=GRAY)
    set_cell_text(right, "Phase B 正式结果报告  2026-10-11", size=8.3, color=GRAY, align=WD_ALIGN_PARAGRAPH.RIGHT)
    set_col_width(left, 3.7)
    set_col_width(right, 3.1)
    for cell in (left, right):
        tc_pr = cell._tc.get_or_add_tcPr()
        borders = OxmlElement("w:tcBorders")
        tc_pr.append(borders)


def build_document():
    result = load_json(RESULT_PATH)
    raw_commit = load_json(RAW_COMMIT_PATH)
    authorization = load_json(AUTH_PATH)

    ratio = float(result["geometricMeanRatio"])
    lower, upper = map(float, result["confidenceIntervalRatio"])
    reduction = 100.0 * (1.0 - ratio)
    reduction_low = 100.0 * (1.0 - upper)
    reduction_high = 100.0 * (1.0 - lower)
    make_ratio_figure(ratio, lower, upper)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    doc = Document()
    section = doc.sections[0]
    section.orientation = WD_ORIENT.PORTRAIT
    section.page_width = Inches(8.5)
    section.page_height = Inches(11)
    section.top_margin = Inches(0.72)
    section.bottom_margin = Inches(0.72)
    section.left_margin = Inches(0.78)
    section.right_margin = Inches(0.78)
    section.header_distance = Inches(0.3)
    section.footer_distance = Inches(0.35)
    add_footer(section)

    styles = doc.styles
    normal = styles["Normal"]
    normal.font.name = FONT_CN
    normal._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_CN)
    normal.font.size = Pt(10.5)
    normal.font.color.rgb = RGBColor.from_string(BLACK)
    normal.paragraph_format.space_after = Pt(5)
    normal.paragraph_format.line_spacing = 1.25

    for style_name, size in (("Title", 22), ("Heading 1", 15), ("Heading 2", 12.5)):
        style = styles[style_name]
        style.font.name = FONT_CN
        style._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_CN)
        style.font.size = Pt(size)
        style.font.bold = True
        style.font.color.rgb = RGBColor.from_string(BLACK)
    remove_paragraph_borders(styles["Title"])

    props = doc.core_properties
    props.title = "Gate 13R P1-C5 独立专项 Phase B 正式确认性结果报告"
    props.subject = "C-FF 与 IDFF 在 P1 指标上的冻结确认性比较"
    props.author = "DDM Final Project Research"
    props.keywords = "Gate 13R, P1, C5, C-FF, IDFF, confirmatory analysis"

    title = doc.add_paragraph(style="Title")
    title.paragraph_format.space_after = Pt(5)
    remove_paragraph_borders(title)
    run = title.add_run("Gate 13R P1-C5 独立专项 Phase B")
    set_run_font(run, FONT_CN, 22, True, BLACK)
    run.add_break()
    run2 = title.add_run("正式确认性结果报告")
    set_run_font(run2, FONT_CN, 22, True, BLACK)

    subtitle = doc.add_paragraph()
    subtitle.paragraph_format.space_after = Pt(3)
    run = subtitle.add_run("C-FF 与 IDFF 在 P1 指标上的冻结比较")
    set_run_font(run, FONT_CN, 12, False, GRAY)

    meta = doc.add_paragraph()
    meta.paragraph_format.space_after = Pt(14)
    run = meta.add_run("研究编号  Gate13R-P1C5-Independent-v1    报告日期  2026-10-11")
    set_run_font(run, FONT_CN, 9.2, False, GRAY)

    intro = doc.add_paragraph()
    intro.paragraph_format.space_after = Pt(10)
    intro.paragraph_format.line_spacing = 1.32
    lead = intro.add_run("正式结论  ")
    set_run_font(lead, FONT_CN, 12, True, NAVY)
    body = intro.add_run(
        "在冻结的 32 个 shared-goal campaign 有限矩阵内，IDFF 的 P1 低于 C-FF。"
        "冻结判定为 IDFF-LOWER-P1-CONFIRMED。"
    )
    set_run_font(body, FONT_CN, 12, True, BLACK)

    add_heading(doc, "结论摘要", 1)
    add_paragraph(
        doc,
        f"IDFF/C-FF 的 P1 几何均值比为 {ratio:.6f}，双侧 95% 置信区间为 "
        f"[{lower:.6f}, {upper:.6f}]，整个区间均低于无差异值 1。按相对差异解释，IDFF 的 P1 约比 "
        f"C-FF 低 {reduction:.2f}%；95% 置信区间对应约低 {reduction_low:.2f}% 至 {reduction_high:.2f}%。"
    )

    table = doc.add_table(rows=1, cols=2)
    set_cell_text(table.rows[0].cells[0], "关键项目", bold=True, color="FFFFFF", align=WD_ALIGN_PARAGRAPH.CENTER)
    set_cell_text(table.rows[0].cells[1], "正式结果", bold=True, color="FFFFFF", align=WD_ALIGN_PARAGRAPH.CENTER)
    rows = [
        ("冻结判定", result["decision"]),
        ("几何均值比  IDFF/C-FF", f"{ratio:.12g}"),
        ("双侧 95% 置信区间", f"[{lower:.12g}, {upper:.12g}]"),
        ("双侧 p 值", f"{float(result['pValueTwoSided']):.12g}"),
    ]
    for label, value in rows:
        cells = table.add_row().cells
        set_cell_text(cells[0], label, size=9.7)
        set_cell_text(cells[1], value, size=9.7, align=WD_ALIGN_PARAGRAPH.CENTER, mono=value.startswith("IDFF-") or "e-" in value)
    style_table(table, [2.55, 4.35])

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(10)
    shape = p.add_run().add_picture(str(FIGURE_PATH), width=Inches(5.75))
    set_picture_alt_text(
        shape,
        "IDFF 与 C-FF 的 P1 比值和置信区间",
        f"IDFF/C-FF 几何均值比 {ratio:.4f}，双侧 95% 置信区间 {lower:.4f} 至 {upper:.4f}，全部低于 1。",
    )
    add_caption(doc, "图 1  IDFF/C-FF 的 P1 几何均值比及双侧 95% 置信区间")

    add_heading(doc, "研究问题与设计", 1)
    add_paragraph(
        doc,
        "本研究回答一个预先指定的问题：在冻结的 32 个 shared-goal campaign 有限矩阵内，"
        "C-FF 与 IDFF 哪一个具有更低的 P1。P1 的机器字段为 dynamicHandlingMillisecondsPerScheduledEvent，"
        "表示每个已调度事件的动态处理时间，单位为毫秒。"
    )

    design_table = doc.add_table(rows=1, cols=2)
    set_cell_text(design_table.rows[0].cells[0], "设计要素", bold=True, color="FFFFFF", align=WD_ALIGN_PARAGRAPH.CENTER)
    set_cell_text(design_table.rows[0].cells[1], "冻结定义", bold=True, color="FFFFFF", align=WD_ALIGN_PARAGRAPH.CENTER)
    design_rows = [
        ("主要终点", "P1  每个已调度事件的动态处理毫秒数  越低越好"),
        ("确认性对比", "IDFF/C-FF"),
        ("独立实验单位", "一个全新 Unity 进程执行的完整两算法成对 block"),
        ("正式样本量", "1,600 个独立成对 blocks  3,200 个算法样本"),
        ("固定矩阵", "32 个 campaigns  每个 campaign 50 个 blocks"),
        ("顺序平衡", "每个 campaign 中 AB 25 个  BA 25 个"),
        ("固定分层", "campaign × AB/BA 顺序  共 64 层  每层 25 个 blocks"),
        ("显著性水平", "双侧 α = 0.05"),
        ("目标把握度", "90%"),
        ("最小检测差异", "对称乘法比值 1.10"),
        ("检验族", "一个预先指定的确认性对比  不作多重性校正"),
    ]
    for label, value in design_rows:
        cells = design_table.add_row().cells
        set_cell_text(cells[0], label, size=9.3)
        set_cell_text(cells[1], value, size=9.3)
    style_table(design_table, [1.75, 5.15], small=True)

    add_heading(doc, "统计方法与判定规则", 1)
    add_paragraph(
        doc,
        "每个合格 block 先计算 P1 的 IDFF/C-FF 自然对数比。分析在每个 campaign 与顺序组合层内计算 block 均值，"
        "再对 64 个层均值等权平均。主要效应以几何均值比报告。"
    )
    add_paragraph(
        doc,
        "方差按照冻结的分层估计式计算，自由度使用 Welch-Satterthwaite 近似，并构造双侧 95% t 置信区间。"
        "置信区间全部低于 1 时判定 IDFF 的 P1 更低；全部高于 1 时判定 C-FF 的 P1 更低；包含 1 时结论为未解决。"
    )
    add_paragraph(
        doc,
        "算法样本是同一 block 内的配对观测，不能被计作两个独立实验单位。正式 n 为 1,600 个成对 blocks。"
    )

    doc.add_page_break()
    add_heading(doc, "主要结果与解释", 1)
    result_table = doc.add_table(rows=1, cols=2)
    set_cell_text(result_table.rows[0].cells[0], "统计量", bold=True, color="FFFFFF", align=WD_ALIGN_PARAGRAPH.CENTER)
    set_cell_text(result_table.rows[0].cells[1], "数值", bold=True, color="FFFFFF", align=WD_ALIGN_PARAGRAPH.CENTER)
    result_rows = [
        ("对数比估计", f"{float(result['estimateLogRatio']):.12f}"),
        ("对数比标准误", f"{float(result['standardErrorLogRatio']):.12f}"),
        ("Welch-Satterthwaite 自由度", f"{float(result['degreesFreedomWelchSatterthwaite']):.6f}"),
        ("t 统计量", f"{float(result['testStatistic']):.6f}"),
        ("双侧 p 值", f"{float(result['pValueTwoSided']):.12g}"),
        ("几何均值比", f"{ratio:.12f}"),
        ("双侧 95% 置信区间", f"[{lower:.12f}, {upper:.12f}]"),
        ("确认性判定", result["decision"]),
    ]
    for label, value in result_rows:
        cells = result_table.add_row().cells
        set_cell_text(cells[0], label, size=9.6)
        set_cell_text(cells[1], value, size=9.6, align=WD_ALIGN_PARAGRAPH.CENTER, mono=True)
    style_table(result_table, [2.85, 4.05])

    add_heading(doc, "结果含义", 2)
    add_paragraph(
        doc,
        "正式估计表明，在预先定义的有限矩阵等权目标下，IDFF 的 P1 为 C-FF 的约 79.51%。"
        "置信区间较窄且完整位于 1 以下，因此方向性判定明确。p 值说明该结果与无差异假设不相容，"
        "但工程意义应主要结合约 20.49% 的相对差异及其置信区间判断，不能只依据 p 值。"
    )

    add_heading(doc, "顺序与场景诊断", 2)
    order_table = doc.add_table(rows=1, cols=3)
    for idx, text in enumerate(("顺序层", "独立 blocks", "IDFF/C-FF 几何均值比")):
        set_cell_text(order_table.rows[0].cells[idx], text, bold=True, color="FFFFFF", align=WD_ALIGN_PARAGRAPH.CENTER)
    for order in ("AB", "BA"):
        entry = result["orderDiagnostics"][order]
        cells = order_table.add_row().cells
        set_cell_text(cells[0], order, size=9.5, align=WD_ALIGN_PARAGRAPH.CENTER)
        set_cell_text(cells[1], entry["pairedBlockCount"], size=9.5, align=WD_ALIGN_PARAGRAPH.CENTER)
        set_cell_text(cells[2], f"{float(entry['geometricMeanRatio']):.6f}", size=9.5, align=WD_ALIGN_PARAGRAPH.CENTER)
    style_table(order_table, [1.35, 1.8, 3.75])
    add_paragraph(
        doc,
        "AB 与 BA 两个顺序层的描述性比值都低于 1，但效应幅度不同。单个 campaign 的描述性比值也分布在 1 的两侧，"
        "提示场景间的效应方向和幅度并不完全一致。这些诊断结果不改变主要判定，也不能用作 campaign 多数票、"
        "选择性删样或事后改变分析规则的依据。"
    )

    doc.add_page_break()
    add_heading(doc, "适用范围", 2)
    add_bullet(doc, "结论只适用于冻结的 32 个 shared-goal campaigns 组成的有限矩阵。")
    add_bullet(doc, "结论只涉及 P1，不代表 IDFF 在所有性能、行为或移动指标上普遍优于 C-FF。")
    add_bullet(doc, "统计确认不等同于机制证明，也不自动等同于所有应用情境中的工程优先选择。")

    add_heading(doc, "数据完整性与执行记录", 1)
    add_paragraph(
        doc,
        "Phase A 完成了全部 1,600 个 Unity 进程和 3,200 个算法样本，并形成不可变原始数据完成提交。"
        "Phase B 在独立授权后单次执行，只读加载原始数据根，并在加载结果前验证原始 payload 文件集合、大小和 SHA-256。"
    )

    integrity_table = doc.add_table(rows=1, cols=2)
    set_cell_text(integrity_table.rows[0].cells[0], "完整性项目", bold=True, color="FFFFFF", align=WD_ALIGN_PARAGRAPH.CENTER)
    set_cell_text(integrity_table.rows[0].cells[1], "记录", bold=True, color="FFFFFF", align=WD_ALIGN_PARAGRAPH.CENTER)
    integrity_rows = [
        ("Phase A 完成时间 UTC", raw_commit["committedAtUtc"]),
        ("正式 Unity 进程", f"{raw_commit['completedUnityProcesses']:,}"),
        ("算法样本", f"{raw_commit['completedAlgorithmSamples']:,}"),
        ("原始 payload 文件", f"{raw_commit['payloadFileCount']:,}"),
        ("原始 payload 字节", f"{raw_commit['payloadBytes']:,}"),
        ("Phase B 执行方式", "冻结分析器  单次执行  无自动重试  不覆盖输出"),
        ("原始数据根", "只读"),
        ("Attempt 4 原始数据", "未合并"),
    ]
    for label, value in integrity_rows:
        cells = integrity_table.add_row().cells
        set_cell_text(cells[0], label, size=9.4)
        set_cell_text(cells[1], value, size=9.4)
    style_table(integrity_table, [2.25, 4.65])

    add_heading(doc, "冻结绑定", 2)
    hash_table = doc.add_table(rows=1, cols=2)
    set_cell_text(hash_table.rows[0].cells[0], "对象", bold=True, color="FFFFFF", align=WD_ALIGN_PARAGRAPH.CENTER)
    set_cell_text(hash_table.rows[0].cells[1], "SHA-256", bold=True, color="FFFFFF", align=WD_ALIGN_PARAGRAPH.CENTER)
    hash_rows = [
        ("Phase B 执行契约", result["executionContractSha256"]),
        ("原始数据完成提交", result["rawDataCompleteSha256"]),
        ("原始 payload manifest", raw_commit["payloadManifestSha256"]),
        ("冻结日程", raw_commit["scheduleSha256"]),
        ("冻结分析器", authorization["analyzerSha256"]),
    ]
    for label, value in hash_rows:
        cells = hash_table.add_row().cells
        set_cell_text(cells[0], label, size=8.8)
        set_cell_text(cells[1], value, size=8.0, mono=True)
    style_table(hash_table, [1.85, 5.05], small=True)

    doc.add_page_break()
    add_heading(doc, "未执行事项", 2)
    add_bullet(doc, "未执行 Gate 14R。")
    add_bullet(doc, "未加载、推导或分析 M1-M5。")
    add_bullet(doc, "未重跑实验，未补样、替换或重排。")
    add_bullet(doc, "未将本研究与 Gate 13R-PR2 attempt 4 的原始数据合并。")

    add_heading(doc, "复核材料", 1)
    add_paragraph(doc, "正式机器可读结果与冻结文件位于以下项目相对路径。")
    paths = [
        "Research/Analysis/Gate13R_P1C5_Independent/v1/confirmatory-p1-c5-result.json",
        "Research/Analysis/Gate13R_P1C5_Independent/v1/confirmatory-p1-c5-report.md",
        "Research/Gate13R_P1C5_Independent_Statistical_Analysis_Plan.v1.md",
        "Research/Gate13R_P1C5_Independent_Execution_Contract.v1.json",
        "Research/Gate13R_P1C5_Independent_PhaseB_Authorization.v1.json",
        "Research/FormalRuns/Gate13R_P1C5_Independent/v1/raw-data-complete.json",
    ]
    for path in paths:
        p = doc.add_paragraph()
        p.paragraph_format.left_indent = Inches(0.15)
        p.paragraph_format.space_after = Pt(2.5)
        run = p.add_run(path)
        set_run_font(run, FONT_MONO, 8.6, False, BLACK)

    add_paragraph(
        doc,
        "本报告是对正式结果的可读整理。若本报告与冻结的机器可读结果出现差异，应以正式 JSON、冻结统计分析计划和执行契约为准。",
        size=9.4,
        color=GRAY,
        space_after=0,
    )

    doc.save(OUTPUT_PATH)
    print(json.dumps({"output": str(OUTPUT_PATH), "figure": str(FIGURE_PATH)}, ensure_ascii=False))


if __name__ == "__main__":
    build_document()
