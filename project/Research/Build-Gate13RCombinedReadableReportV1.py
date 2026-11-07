#!/usr/bin/env python3
"""Build a readable Chinese DOCX combining Gate 13R attempt 4 and P1-C5 results."""

from __future__ import annotations

import importlib.util
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from docx import Document
from docx.enum.section import WD_ORIENT
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


PROJECT = Path(r"H:\DDM_Final_Project")
RESEARCH = PROJECT / "Research"
BASE_BUILDER_PATH = RESEARCH / "Build-Gate13RP1C5PhaseBReadableReportV1.py"

ATTEMPT4_DIR = RESEARCH / "Analysis/Gate13R_PR2_Attempt4_PhaseB/v1"
ATTEMPT4_PRIMARY_PATH = ATTEMPT4_DIR / "shared-primary-p1-analysis.json"
ATTEMPT4_SUPPORTIVE_PATH = ATTEMPT4_DIR / "shared-supportive-p2-p5-analysis.json"
ATTEMPT4_HETERO_PATH = ATTEMPT4_DIR / "heterogeneous-secondary-analysis.json"
ATTEMPT4_COVERAGE_PATH = ATTEMPT4_DIR / "schedule-coverage-and-missingness.json"
ATTEMPT4_INPUT_AUDIT_PATH = ATTEMPT4_DIR / "analysis-input-audit.json"
ATTEMPT4_RECEIPT_PATH = ATTEMPT4_DIR / "phase-b-execution-receipt.json"
ATTEMPT4_MANIFEST_PATH = ATTEMPT4_DIR / "phase-b-analysis-manifest.json"
ATTEMPT4_RAW_RECEIPT_PATH = RESEARCH / "FormalRuns/Gate13R_RQAligned_S48H48/v4/raw-data-freeze-receipt.json"

P1C5_RESULT_PATH = RESEARCH / "Analysis/Gate13R_P1C5_Independent/v1/confirmatory-p1-c5-result.json"
P1C5_RAW_COMMIT_PATH = RESEARCH / "FormalRuns/Gate13R_P1C5_Independent/v1/raw-data-complete.json"
P1C5_DESIGN_PATH = RESEARCH / "Gate13R_P1C5_Independent_Design.v1.json"

OUTPUT_DIR = RESEARCH / "Reports/Gate13R_Combined/v1"
OUTPUT_PATH = OUTPUT_DIR / "Gate13R_Attempt4_and_P1C5_Combined_Results_Readable_Report.zh-CN.docx"
BUILD_DIR = PROJECT / ".codex_tmp/gate13r_combined_readable_report"
FIGURE_PATH = BUILD_DIR / "p1_confirmatory_forest.png"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def load_base_builder():
    spec = importlib.util.spec_from_file_location("gate13r_report_base", BASE_BUILDER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load base builder: {BASE_BUILDER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


B = load_base_builder()


def fmt_ratio(value: float) -> str:
    return f"{float(value):.4f}"


def fmt_ci(values) -> str:
    lo, hi = (float(values[0]), float(values[1]))
    return f"[{lo:.4f}, {hi:.4f}]"


def fmt_p(value: float) -> str:
    value = float(value)
    if value < 0.0001:
        return f"{value:.3e}"
    return f"{value:.4f}"


def add_footer(section):
    footer = section.footer
    table = footer.add_table(rows=1, cols=2, width=Inches(6.8))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    left, right = table.rows[0].cells
    B.set_cell_text(left, "Gate 13R Results Synthesis", size=8.2, color=B.GRAY)
    B.set_cell_text(
        right,
        "attempt 4 与 P1 C5 独立专项  2026-10-11",
        size=8.2,
        color=B.GRAY,
        align=WD_ALIGN_PARAGRAPH.RIGHT,
    )
    B.set_col_width(left, 3.3)
    B.set_col_width(right, 3.5)
    for cell in (left, right):
        tc_pr = cell._tc.get_or_add_tcPr()
        borders = OxmlElement("w:tcBorders")
        tc_pr.append(borders)


def add_table(doc, headers, rows, widths, *, center_cols=(), mono_cols=(), font_size=9.0, small=False):
    table = doc.add_table(rows=1, cols=len(headers))
    for idx, header in enumerate(headers):
        B.set_cell_text(
            table.rows[0].cells[idx],
            header,
            bold=True,
            color="FFFFFF",
            align=WD_ALIGN_PARAGRAPH.CENTER,
            size=9.0 if small else 9.4,
        )
    for row_values in rows:
        cells = table.add_row().cells
        for idx, value in enumerate(row_values):
            B.set_cell_text(
                cells[idx],
                value,
                size=font_size,
                align=WD_ALIGN_PARAGRAPH.CENTER if idx in center_cols else WD_ALIGN_PARAGRAPH.LEFT,
                mono=idx in mono_cols,
            )
    B.style_table(table, widths, small=small)
    return table


def get_contrast(metric: dict, contrast_id: str) -> dict:
    for item in metric["contrasts"]:
        if item["contrast"]["id"] == contrast_id:
            return item
    raise KeyError(f"contrast not found: {contrast_id}")


def make_forest_figure(primary: dict, independent: dict):
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    p1 = primary["metric"]
    rows = []
    for contrast_id in ("C1", "C2", "C3", "C4", "C5"):
        item = get_contrast(p1, contrast_id)
        estimate = item["matrixEstimate"]
        label = f"attempt 4  {contrast_id}  {item['contrast']['numerator']}/{item['contrast']['denominator']}"
        rows.append(
            {
                "label": label,
                "ratio": float(estimate["geometricRatio"]),
                "ci": tuple(map(float, estimate["bonferroniCompatible99CiRatioScale"])),
                "kind": "primary" if contrast_id != "C5" else "unresolved",
                "ci_label": "99% simultaneous CI",
            }
        )
    rows.append(
        {
            "label": "P1 C5 独立专项  IDFF/C-FF",
            "ratio": float(independent["geometricMeanRatio"]),
            "ci": tuple(map(float, independent["confidenceIntervalRatio"])),
            "kind": "independent",
            "ci_label": "95% CI",
        }
    )

    width, height = 1800, 920
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)
    font_regular = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 31)
    font_small = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 25)
    font_tiny = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 22)
    font_bold = ImageFont.truetype(r"C:\Windows\Fonts\msyhbd.ttc", 43)

    navy = (31, 78, 121)
    blue = (91, 155, 213)
    gray = (110, 110, 110)
    red = (170, 60, 60)
    black = (35, 35, 35)

    draw.text((70, 34), "P1 正式对比的几何均值比", font=font_bold, fill=navy)
    draw.text((70, 94), "比值小于 1 表示分子算法的 P1 更低", font=font_small, fill=(85, 85, 85))

    x_min, x_max = 0.05, 2.0
    axis_left, axis_right = 690, 1510
    axis_top, axis_bottom = 165, 715

    def xpos(value: float) -> float:
        return axis_left + (math.log10(value) - math.log10(x_min)) / (math.log10(x_max) - math.log10(x_min)) * (axis_right - axis_left)

    null_x = xpos(1.0)
    y = axis_top - 15
    while y < axis_bottom + 12:
        draw.line((null_x, y, null_x, min(y + 14, axis_bottom + 12)), fill=red, width=3)
        y += 24
    draw.text((null_x - 52, axis_top - 48), "无差异 1", font=font_tiny, fill=red)

    ticks = [0.05, 0.1, 0.2, 0.5, 1.0, 2.0]
    draw.line((axis_left, axis_bottom, axis_right, axis_bottom), fill=(90, 90, 90), width=3)
    for tick in ticks:
        x = xpos(tick)
        draw.line((x, axis_bottom - 9, x, axis_bottom + 9), fill=(90, 90, 90), width=2)
        label = f"{tick:g}"
        box = draw.textbbox((0, 0), label, font=font_tiny)
        draw.text((x - (box[2] - box[0]) / 2, axis_bottom + 18), label, font=font_tiny, fill=(70, 70, 70))

    y_positions = [190, 282, 374, 466, 558, 665]
    for index, (row, y) in enumerate(zip(rows, y_positions)):
        if index == 5:
            draw.line((60, y - 47, 1710, y - 47), fill=(210, 210, 210), width=2)
        color = navy if row["kind"] in {"primary", "independent"} else gray
        point_fill = blue if row["kind"] == "primary" else navy if row["kind"] == "independent" else (170, 170, 170)
        draw.text((70, y - 20), row["label"], font=font_regular, fill=black)
        low_x, high_x, est_x = xpos(row["ci"][0]), xpos(row["ci"][1]), xpos(row["ratio"])
        draw.line((low_x, y, high_x, y), fill=color, width=8)
        draw.line((low_x, y - 15, low_x, y + 15), fill=color, width=5)
        draw.line((high_x, y - 15, high_x, y + 15), fill=color, width=5)
        if row["kind"] == "independent":
            diamond = [(est_x, y - 18), (est_x + 18, y), (est_x, y + 18), (est_x - 18, y)]
            draw.polygon(diamond, fill=point_fill, outline=navy)
        else:
            draw.ellipse((est_x - 13, y - 13, est_x + 13, y + 13), fill=point_fill, outline=color, width=3)
        draw.text((1518, y - 29), f"{row['ratio']:.4f}  {row['ci_label']}", font=font_tiny, fill=color)
        draw.text((1518, y + 3), fmt_ci(row["ci"]), font=font_tiny, fill=color)

    draw.text((70, 800), "attempt 4 的区间为五个 P1 对比的 Bonferroni compatible 99% 同时区间", font=font_tiny, fill=gray)
    draw.text((70, 842), "独立专项的区间为单一预先指定对比的双侧 95% t 置信区间", font=font_tiny, fill=gray)
    image.save(FIGURE_PATH, format="PNG", dpi=(300, 300))


def build_document():
    primary = load_json(ATTEMPT4_PRIMARY_PATH)
    supportive = load_json(ATTEMPT4_SUPPORTIVE_PATH)
    heterogeneous = load_json(ATTEMPT4_HETERO_PATH)
    coverage = load_json(ATTEMPT4_COVERAGE_PATH)
    input_audit = load_json(ATTEMPT4_INPUT_AUDIT_PATH)
    attempt4_receipt = load_json(ATTEMPT4_RECEIPT_PATH)
    attempt4_manifest = load_json(ATTEMPT4_MANIFEST_PATH)
    attempt4_raw = load_json(ATTEMPT4_RAW_RECEIPT_PATH)
    p1c5 = load_json(P1C5_RESULT_PATH)
    p1c5_raw = load_json(P1C5_RAW_COMMIT_PATH)
    p1c5_design = load_json(P1C5_DESIGN_PATH)

    make_forest_figure(primary, p1c5)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    doc = Document()
    section = doc.sections[0]
    section.orientation = WD_ORIENT.PORTRAIT
    section.page_width = Inches(8.5)
    section.page_height = Inches(11)
    section.top_margin = Inches(0.68)
    section.bottom_margin = Inches(0.70)
    section.left_margin = Inches(0.76)
    section.right_margin = Inches(0.76)
    section.header_distance = Inches(0.30)
    section.footer_distance = Inches(0.34)
    add_footer(section)

    styles = doc.styles
    normal = styles["Normal"]
    normal.font.name = B.FONT_CN
    normal._element.rPr.rFonts.set(qn("w:eastAsia"), B.FONT_CN)
    normal.font.size = Pt(10.5)
    normal.font.color.rgb = RGBColor.from_string(B.BLACK)
    normal.paragraph_format.space_after = Pt(5)
    normal.paragraph_format.line_spacing = 1.25
    for style_name, size in (("Title", 21), ("Heading 1", 15), ("Heading 2", 12.5)):
        style = styles[style_name]
        style.font.name = B.FONT_CN
        style._element.rPr.rFonts.set(qn("w:eastAsia"), B.FONT_CN)
        style.font.size = Pt(size)
        style.font.bold = True
        style.font.color.rgb = RGBColor.from_string(B.BLACK)
    B.remove_paragraph_borders(styles["Title"])

    props = doc.core_properties
    props.title = "Gate 13R attempt 4 与 P1 C5 独立专项结果综合报告"
    props.subject = "Gate 13R 两项冻结研究的正式结果与证据边界"
    props.author = "DDM Final Project Research"
    props.keywords = "Gate 13R, attempt 4, P1 C5, C-FF, IDFF, confirmatory, supportive"

    title = doc.add_paragraph(style="Title")
    title.paragraph_format.space_after = Pt(5)
    B.remove_paragraph_borders(title)
    run = title.add_run("Gate 13R attempt 4 与 P1 C5 独立专项")
    B.set_run_font(run, B.FONT_CN, 21, True, B.BLACK)
    run.add_break()
    run2 = title.add_run("结果综合报告")
    B.set_run_font(run2, B.FONT_CN, 21, True, B.BLACK)

    subtitle = doc.add_paragraph()
    subtitle.paragraph_format.space_after = Pt(3)
    B.set_run_font(subtitle.add_run("两项冻结研究的正式结论 支持性结果与适用边界"), B.FONT_CN, 11.8, False, B.GRAY)
    meta = doc.add_paragraph()
    meta.paragraph_format.space_after = Pt(12)
    B.set_run_font(meta.add_run("报告日期  2026-10-11    研究范围  Gate 13R"), B.FONT_CN, 9.2, False, B.GRAY)

    intro = doc.add_paragraph()
    intro.paragraph_format.space_after = Pt(9)
    intro.paragraph_format.line_spacing = 1.30
    B.set_run_font(intro.add_run("综合结论  "), B.FONT_CN, 12, True, B.NAVY)
    B.set_run_font(
        intro.add_run(
            "attempt 4 在 P1 上确认 C-FF 和 IDFF 分别低于 A*-R 与 D*L，但其 C5 对比未能确认 C-FF 与 IDFF 谁更低。"
            "随后开展的 P1 C5 独立专项使用全新数据，确认 IDFF 的 P1 低于 C-FF。"
        ),
        B.FONT_CN,
        12,
        True,
        B.BLACK,
    )

    B.add_heading(doc, "结果总览", 1)
    overview_rows = [
        ("attempt 4", "P1 确认性 C1 至 C4", "四项均满足优效标准", "C-FF 与 IDFF 均低于两个基线算法"),
        ("attempt 4", "P1 确认性 C5", "未解决", "IDFF/C-FF 比值 0.7986  同时区间包含 1"),
        ("P1 C5 独立专项", "单一确认性 C5", "IDFF 的 P1 更低", "比值 0.7951  95% CI 0.7884 至 0.8018"),
        ("全部现有研究", "Gate 14R 与 M1 至 M5", "未执行", "不能据此判断移动表现或全指标总赢家"),
    ]
    add_table(
        doc,
        ("研究", "证据层级", "正式状态", "读法"),
        overview_rows,
        (1.25, 1.65, 1.55, 2.55),
        center_cols=(0, 2),
        font_size=8.6,
        small=True,
    )

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(9)
    shape = p.add_run().add_picture(str(FIGURE_PATH), width=Inches(6.0))
    B.set_picture_alt_text(
        shape,
        "Gate 13R P1 正式对比",
        "attempt 4 的五个 P1 对比及 P1 C5 独立专项的几何均值比和相应置信区间。attempt 4 C1 至 C4 区间低于 1，attempt 4 C5 区间跨过 1，独立专项 C5 区间低于 1。",
    )
    B.add_caption(doc, "图 1  两项研究中的 P1 正式对比及各自冻结区间")

    heading = B.add_heading(doc, "结论层级与研究关系", 1)
    heading.paragraph_format.page_break_before = True
    evidence_rows = [
        ("attempt 4 共享目标 P1", "确认性", "C1 至 C5 的预先冻结检验族  Holm 校正与 99% 同时区间"),
        ("attempt 4 共享目标 P2 至 P5", "支持性", "描述效应与不确定性  禁止升级为 P1 确认性结论"),
        ("attempt 4 异质场景", "次要或诊断性", "21 个冻结场景的系统处理分析  禁止确认性晋升"),
        ("P1 C5 独立专项", "独立确认性", "一个预先指定双侧对比  使用全新数据且不与 attempt 4 合并"),
    ]
    add_table(doc, ("结果来源", "角色", "正式边界"), evidence_rows, (2.15, 1.25, 3.6), center_cols=(1,), font_size=9.0)
    B.add_paragraph(
        doc,
        "两个研究使用不同的冻结执行契约和独立数据谱系。P1 C5 独立专项不是 attempt 4 的补样、重试或重新分析，"
        "也没有把 attempt 4 原始数据并入新的专项结果。它回答的是 attempt 4 中预先定义但未解决的 C5 问题。",
    )
    B.add_paragraph(
        doc,
        "attempt 4 的 C5 点估计为 0.7986，独立专项的点估计为 0.7951。两者方向和幅度相近，但正式判定取决于各自冻结的"
        "实验单位、方差估计、检验族与置信区间。attempt 4 的 99% 同时区间跨过 1，因此未解决；独立专项的 95% 区间完整低于 1，因此确认 IDFF 的 P1 更低。",
    )

    B.add_heading(doc, "指标定义", 1)
    metric_rows = [
        ("P1", "每个已调度事件的动态处理毫秒数", "越低越好", "attempt 4 确认性  专项确认性"),
        ("P2", "动态处理时长的样本内事件级 P95", "越低越好", "支持性"),
        ("P3", "每个 agent 的总规划时间及独立的规模斜率", "时间和斜率越低越好", "支持性"),
        ("P4", "每个已调度事件的动态托管分配字节数", "越低越好", "支持性"),
        ("P5", "按操作类型划分的预算超限率", "越低越好", "支持性计数或比率"),
    ]
    add_table(doc, ("指标", "定义", "方向", "本报告中的角色"), metric_rows, (0.65, 3.1, 1.25, 2.0), center_cols=(0, 2, 3), font_size=8.7, small=True)

    heading = B.add_heading(doc, "Gate 13R attempt 4 设计与完整性", 1)
    heading.paragraph_format.page_break_before = True
    attempt4_design_rows = [
        ("正式规模", "3,552 个 Unity 进程  10,176 个算法样本"),
        ("共享目标部分", "32 个 campaigns  每个 48 个 blocks  1,536 个进程  6,144 个样本"),
        ("异质场景部分", "21 个场景  1,008 个 matched superblocks  2,016 个进程  4,032 个样本"),
        ("共享算法", "A*-R  D*L  IDFF  C-FF"),
        ("共享矩阵加权", "32 个冻结 campaign 等权"),
        ("异质矩阵加权", "21 个冻结异质场景等权"),
        ("自动恢复", "0 次"),
        ("缺失与资格", "3,552 个进程及 10,176 个样本全部完成且合格"),
    ]
    add_table(doc, ("设计项目", "冻结记录"), attempt4_design_rows, (2.0, 5.0), font_size=9.2)

    B.add_heading(doc, "执行完整性", 2)
    B.add_paragraph(
        doc,
        f"Phase B 验证了 {input_audit['payloadVerification']['verifiedFileCount']:,} 个原始 payload 文件，"
        f"共 {input_audit['payloadVerification']['verifiedRawBytes']:,} 字节。分析前后的原始根文件数、字节数和元数据 SHA-256 完全一致，"
        "因此正式记录为 rawRootUnchanged 和 rawMetadataUnchangedDuringAnalysis。",
    )
    integrity_rows = [
        ("原始数据完成时间 UTC", attempt4_raw["committedAtUtc"]),
        ("原始 payload 文件", f"{attempt4_raw['rawPayloadFileCount']:,}"),
        ("原始 payload 字节", f"{attempt4_raw['rawPayloadOriginalBytes']:,}"),
        ("Phase B 状态", attempt4_receipt["status"]),
        ("原始根在分析期间", "未改变" if input_audit["rawMetadataUnchangedDuringAnalysis"] else "记录不一致"),
        ("Gate 14R", "未授权且未执行"),
        ("M1 至 M5", "未加载且未推导"),
    ]
    add_table(doc, ("完整性项目", "记录"), integrity_rows, (2.25, 4.75), font_size=8.9)

    heading = B.add_heading(doc, "attempt 4 的确认性 P1 结果", 1)
    heading.paragraph_format.page_break_before = True
    B.add_paragraph(
        doc,
        "共享目标矩阵的 P1 确认性检验族包含五个预先冻结对比。C1 至 C4 为单侧优效性问题，正式判定同时要求方向有利、"
        "Holm 校正 p 值低于 0.05、99% 同时区间上界低于 1，并通过正确性与结构门禁。C5 为双侧报告，不允许根据结果事后加注赢家标签。",
    )
    primary_rows = []
    for cid in ("C1", "C2", "C3", "C4", "C5"):
        item = get_contrast(primary["metric"], cid)
        estimate = item["matrixEstimate"]
        comparison = f"{item['contrast']['numerator']}/{item['contrast']['denominator']}"
        if cid == "C5":
            verdict = "未解决  同时区间包含 1"
        else:
            verdict = "优效标准满足"
        primary_rows.append(
            (
                cid,
                comparison,
                fmt_ratio(estimate["geometricRatio"]),
                fmt_ci(estimate["bonferroniCompatible99CiRatioScale"]),
                fmt_p(estimate["holmAdjustedPValue"]),
                verdict,
            )
        )
    add_table(
        doc,
        ("对比", "分子/分母", "几何均值比", "99% 同时区间", "Holm p", "正式判定"),
        primary_rows,
        (0.55, 1.2, 1.05, 1.65, 1.0, 1.55),
        center_cols=(0, 1, 2, 3, 4, 5),
        mono_cols=(2, 3, 4),
        font_size=8.0,
        small=True,
    )
    B.add_heading(doc, "确认性读法", 2)
    B.add_bullet(doc, "C1 和 C2 确认 C-FF 的 P1 分别低于 A*-R 与 D*L。")
    B.add_bullet(doc, "C3 和 C4 确认 IDFF 的 P1 分别低于 A*-R 与 D*L。")
    B.add_bullet(doc, "C5 的点估计偏向 IDFF，但 99% 同时区间为 0.4623 至 1.3797，Holm 校正 p 值为 0.2894，因此 attempt 4 本身不能确认 C-FF 与 IDFF 谁更低。")
    B.add_paragraph(
        doc,
        "每个共享 campaign 有 48 个合格 Williams blocks，共 1,536 个底层 blocks。矩阵估计对 32 个冻结 campaign 均值等权，"
        "正式输出中的矩阵级 nIndependentUnits 为 32。不能把 6,144 个算法样本当作彼此独立的确认性 n。",
    )

    heading = B.add_heading(doc, "attempt 4 的支持性和次要结果", 1)
    heading.paragraph_format.page_break_before = True
    B.add_heading(doc, "共享目标 C5 支持性结果", 2)
    supportive_by_id = {m["metricId"]: m for m in supportive["continuousMetrics"]}
    supportive_rows = []
    for metric_id, label in (("P2", "P2 尾部时延"), ("P3-PER-AGENT", "P3 每 agent 时间"), ("P4", "P4 分配压力")):
        item = get_contrast(supportive_by_id[metric_id], "C5")
        estimate = item["matrixEstimate"]
        ratio = float(estimate["geometricRatio"])
        ci = tuple(map(float, estimate["unadjusted95CiRatioScale"]))
        if ci[1] < 1:
            reading = "IDFF 较低"
        elif ci[0] > 1:
            reading = "IDFF 较高"
        else:
            reading = "区间包含 1"
        supportive_rows.append((label, fmt_ratio(ratio), fmt_ci(ci), reading))
    slope_c5 = next(item for item in supportive["p3ScalingSlope"]["contrastSlopeDifferences"] if item["contrast"]["id"] == "C5")
    slope = slope_c5["slopeDifferenceSummary"]
    supportive_rows.append(
        (
            "P3 规模斜率差",
            f"{float(slope['pointEstimate']):.4f}",
            f"[{float(slope['unadjusted95Ci'][0]):.4f}, {float(slope['unadjusted95Ci'][1]):.4f}]",
            "IDFF 斜率较低",
        )
    )
    add_table(doc, ("支持性指标", "IDFF/C-FF 或差值", "未校正 95% 区间", "描述性读法"), supportive_rows, (1.75, 1.55, 1.85, 1.85), center_cols=(1, 2, 3), mono_cols=(1, 2), font_size=8.7, small=True)
    B.add_paragraph(
        doc,
        "这些结果显示 P2 的区间包含 1，P3 每 agent 时间对 IDFF 不利，P3 规模斜率和 P4 对 IDFF 有利。它们属于支持性输出，"
        "没有进入 P1 的 Holm 检验族，也不能合并成多数票或全局赢家。",
    )
    p5_shared = supportive["p5CountsAndRates"]["matrixTotals"]
    B.add_paragraph(
        doc,
        f"P5 共享目标矩阵中，四个算法的 OVERALL 超限事件均为 0/{p5_shared['IDFF']['OVERALL']['denominator']:,}。"
        f"零事件时的单侧 95% 上界为 {p5_shared['IDFF']['OVERALL']['exactOneSided95UpperIfZeroEvents']:.3e}。"
        "冻结规则明确禁止用全零结果宣布算法优效或未来风险为零。",
    )

    B.add_heading(doc, "异质场景次要结果", 2)
    hetero_by_id = {m["metricId"]: m for m in heterogeneous["continuousMetrics"]}
    hetero_rows = []
    for metric_id, label in (("P1", "P1"), ("P2", "P2"), ("P3-PER-AGENT", "P3 每 agent"), ("P4", "P4")):
        item = get_contrast(hetero_by_id[metric_id], "C5")
        estimate = item["matrixSecondaryEstimate"]
        ratio = float(estimate["geometricRatio"])
        ci = tuple(map(float, estimate["unadjusted95CiRatioScale"]))
        reading = "IDFF 较低" if ci[1] < 1 else "IDFF 较高" if ci[0] > 1 else "区间包含 1"
        hetero_rows.append((label, fmt_ratio(ratio), fmt_ci(ci), reading))
    add_table(doc, ("指标", "IDFF/C-FF", "未校正 95% 区间", "描述性读法"), hetero_rows, (1.25, 1.45, 2.2, 2.1), center_cols=(0, 1, 2, 3), mono_cols=(1, 2), font_size=8.7, small=True)
    B.add_paragraph(
        doc,
        "异质场景矩阵包含 21 个冻结场景和 1,008 个 matched superblocks。P1、P2 与 P4 的 C5 区间低于 1，"
        "P3 每 agent 时间的区间包含 1。以上结果全部标记为 secondary or diagnostic，不属于 P1 Holm 家族，不能晋升为确认性结论。",
    )
    p5_hetero = heterogeneous["p5CountsAndRates"]["matrixTotals"]
    B.add_paragraph(
        doc,
        f"异质场景 P5 中，四个算法的 OVERALL 超限事件同样均为 0/{p5_hetero['IDFF']['OVERALL']['denominator']:,}；"
        "该全零记录仍不允许产生优效结论。",
    )

    heading = B.add_heading(doc, "P1 C5 独立专项", 1)
    heading.paragraph_format.page_break_before = True
    B.add_paragraph(
        doc,
        "该专项只回答一个问题：在冻结的 32 个 shared goal campaign 有限矩阵内，C-FF 与 IDFF 哪一个具有更低的 P1。"
        "研究使用全新 Unity 进程和独立原始数据根，不合并 attempt 4 数据。",
    )
    p1c5_design_rows = [
        ("确认性对比", "IDFF/C-FF  双侧 α 等于 0.05"),
        ("固定矩阵", "32 个 campaigns  每个 campaign 50 个全新成对 blocks"),
        ("正式规模", "1,600 个独立 paired blocks  3,200 个算法样本"),
        ("独立实验单位", "一个全新 Unity 进程执行的完整两算法成对 block"),
        ("顺序平衡", "每个 campaign 中 AB 25 个  BA 25 个"),
        ("固定分层", "campaign 与 AB BA 顺序  共 64 层  每层 25 个 blocks"),
        ("目标把握度", "90%"),
        ("最小检测差异", "对称乘法比值 1.10"),
        ("多重性", "单一预先指定对比  不作校正"),
    ]
    add_table(doc, ("设计项目", "冻结定义"), p1c5_design_rows, (2.0, 5.0), font_size=9.0)

    B.add_heading(doc, "专项确认性结果", 1)
    p1c5_rows = [
        ("正式判定", p1c5["decision"]),
        ("IDFF/C-FF 几何均值比", f"{float(p1c5['geometricMeanRatio']):.12f}"),
        ("双侧 95% 置信区间", f"[{float(p1c5['confidenceIntervalRatio'][0]):.12f}, {float(p1c5['confidenceIntervalRatio'][1]):.12f}]"),
        ("双侧 p 值", f"{float(p1c5['pValueTwoSided']):.12g}"),
        ("t 统计量", f"{float(p1c5['testStatistic']):.6f}"),
        ("Welch Satterthwaite 自由度", f"{float(p1c5['degreesFreedomWelchSatterthwaite']):.6f}"),
    ]
    add_table(doc, ("统计项目", "正式结果"), p1c5_rows, (2.65, 4.35), center_cols=(1,), mono_cols=(1,), font_size=9.2)
    reduction = 100.0 * (1.0 - float(p1c5["geometricMeanRatio"]))
    reduction_low = 100.0 * (1.0 - float(p1c5["confidenceIntervalRatio"][1]))
    reduction_high = 100.0 * (1.0 - float(p1c5["confidenceIntervalRatio"][0]))
    B.add_paragraph(
        doc,
        f"在专项冻结的有限矩阵等权目标下，IDFF 的 P1 估计为 C-FF 的 {float(p1c5['geometricMeanRatio']) * 100:.2f}%。"
        f"换算为相对差异，IDFF 的 P1 约低 {reduction:.2f}%，95% 置信区间对应约低 {reduction_low:.2f}% 至 {reduction_high:.2f}%。"
        "置信区间完整低于 1，因此冻结判定为 IDFF-LOWER-P1-CONFIRMED。",
    )
    B.add_heading(doc, "顺序层诊断", 2)
    order_rows = [
        ("AB", f"{p1c5['orderDiagnostics']['AB']['pairedBlockCount']:,}", fmt_ratio(p1c5["orderDiagnostics"]["AB"]["geometricMeanRatio"])),
        ("BA", f"{p1c5['orderDiagnostics']['BA']['pairedBlockCount']:,}", fmt_ratio(p1c5["orderDiagnostics"]["BA"]["geometricMeanRatio"])),
    ]
    add_table(doc, ("顺序层", "独立 blocks", "IDFF/C-FF 几何均值比"), order_rows, (1.4, 1.8, 3.8), center_cols=(0, 1, 2), mono_cols=(2,), font_size=9.2)
    B.add_paragraph(
        doc,
        "AB 与 BA 两个顺序层的描述性比值均低于 1，但幅度不同。顺序层和单个 campaign 诊断不改变主要确认性判定，"
        "也不能用作删样、补样或重排依据。",
    )

    B.add_heading(doc, "两项研究的合并读法", 1)
    B.add_heading(doc, "目前能够确认的结论", 2)
    B.add_bullet(doc, "attempt 4 的共享目标 P1 分析确认 C-FF 相对 A*-R 与 D*L 的四项优效条件均满足。")
    B.add_bullet(doc, "attempt 4 的共享目标 P1 分析确认 IDFF 相对 A*-R 与 D*L 的四项优效条件均满足。")
    B.add_bullet(doc, "P1 C5 独立专项确认 IDFF 的 P1 低于 C-FF，适用范围是专项冻结的 32 campaign 有限矩阵。")
    B.add_paragraph(
        doc,
        "这些确认性结论可以共同用于理解 P1，但来自两个不同的冻结研究。由于两项研究没有合并原始数据，也没有建立一个新的联合多重性家族，"
        "本报告不把它们改写为一个新检验或新的全局排行榜。",
    )

    B.add_heading(doc, "目前只能支持性描述的结果", 2)
    B.add_paragraph(
        doc,
        "attempt 4 的 P2 至 P5 和异质场景结果用于补充理解尾部时延、规模行为、分配压力和预算超限。它们显示不同指标上的方向并不一致，"
        "因此不能据此宣布某个算法在所有性能维度上普遍优于其他算法。",
    )

    B.add_heading(doc, "当前不能作出的结论", 2)
    B.add_bullet(doc, "不能把 P1 的确认性结果外推为所有未纳入 campaign 的普遍规律。")
    B.add_bullet(doc, "不能从 P1 至 P5 推导移动完成率、路径效率、帧时间或移动失败率。")
    B.add_bullet(doc, "不能把 P2 至 P5 的支持性方向当作新的确认性检验。")
    B.add_bullet(doc, "不能用 P5 全零记录证明未来超限概率为零或证明算法优效。")
    B.add_bullet(doc, "不能据此执行或替代 Gate 14R，也不能声称 M1 至 M5 已获得数据。")

    heading = B.add_heading(doc, "研究状态", 1)
    heading.paragraph_format.page_break_before = True
    status_rows = [
        ("Gate 13R attempt 4 Phase A", "完成  原始数据冻结"),
        ("Gate 13R attempt 4 Phase B", "完成  正式分析输出已提交"),
        ("P1 C5 独立专项 Phase A", "完成  原始数据冻结"),
        ("P1 C5 独立专项 Phase B", "完成  IDFF-LOWER-P1-CONFIRMED"),
        ("Gate 14R", "未授权且未执行"),
        ("M1 至 M5", "未授权  未加载  未推导  未分析"),
    ]
    add_table(doc, ("阶段", "当前状态"), status_rows, (3.0, 4.0), font_size=8.5, small=True)

    B.add_heading(doc, "冻结绑定与复核材料", 1)
    binding_rows = [
        ("attempt 4 Phase B 执行契约", attempt4_receipt["contractSha256"]),
        ("attempt 4 Phase B 分析清单", attempt4_receipt["analysisManifestSha256"]),
        ("attempt 4 原始 payload 树", input_audit["rawRootCanonicalTreeSha256"]),
        ("P1 C5 专项执行契约", p1c5["executionContractSha256"]),
        ("P1 C5 原始数据完成提交", p1c5["rawDataCompleteSha256"]),
        ("P1 C5 原始 payload manifest", p1c5_raw["payloadManifestSha256"]),
        ("P1 C5 冻结日程", p1c5_raw["scheduleSha256"]),
    ]
    add_table(doc, ("冻结对象", "SHA-256"), binding_rows, (2.3, 4.7), mono_cols=(1,), font_size=7.2, small=True)

    B.add_heading(doc, "复核路径", 1)
    review_paths = [
        "Research/Analysis/Gate13R_PR2_Attempt4_PhaseB/v1/shared-primary-p1-analysis.json",
        "Research/Analysis/Gate13R_PR2_Attempt4_PhaseB/v1/shared-supportive-p2-p5-analysis.json",
        "Research/Analysis/Gate13R_PR2_Attempt4_PhaseB/v1/heterogeneous-secondary-analysis.json",
        "Research/Analysis/Gate13R_PR2_Attempt4_PhaseB/v1/schedule-coverage-and-missingness.json",
        "Research/Analysis/Gate13R_PR2_Attempt4_PhaseB/v1/phase-b-execution-receipt.json",
        "Research/Analysis/Gate13R_P1C5_Independent/v1/confirmatory-p1-c5-result.json",
        "Research/Analysis/Gate13R_P1C5_Independent/v1/confirmatory-p1-c5-report.md",
        "Research/Gate13R_P1C5_Independent_Statistical_Analysis_Plan.v1.md",
        "Research/FormalRuns/Gate13R_P1C5_Independent/v1/raw-data-complete.json",
    ]
    B.add_paragraph(doc, "正式机器可读结果、执行收据和冻结计划位于以下项目相对路径。")
    for path in review_paths:
        paragraph = doc.add_paragraph()
        paragraph.paragraph_format.left_indent = Inches(0.15)
        paragraph.paragraph_format.space_after = Pt(0.5)
        B.set_run_font(paragraph.add_run(path), B.FONT_MONO, 7.7, False, B.BLACK)

    note = doc.add_paragraph()
    note.paragraph_format.space_before = Pt(3)
    note.paragraph_format.space_after = Pt(0)
    note.paragraph_format.line_spacing = 1.1
    B.set_run_font(
        note.add_run(
            "本报告是两项正式结果的可读整理。若本报告与冻结机器可读结果、统计分析计划或执行契约不一致，"
            "以对应研究的正式 JSON、冻结计划和契约为准。"
        ),
        B.FONT_CN,
        8.8,
        False,
        B.GRAY,
    )

    doc.save(OUTPUT_PATH)
    print(json.dumps({"output": str(OUTPUT_PATH), "figure": str(FIGURE_PATH)}, ensure_ascii=False))


if __name__ == "__main__":
    build_document()
