# Gate14Re-ME 第 8 项：需要作者科学参数

当前状态：`FAIL_CLOSED_AUTHOR_INPUT_NEEDED_BEFORE_FINAL_B`。

qualification、独立只读验收和运行时工程诊断已经通过。工程预算表也已完成：B=36 的 20% 头寸预算为 83.493 小时，B=72 为 166.987 小时；B=108 和 B=144 触发 168 小时门。

这些运行时数字不能证明统计功效。冻结协议要求先给出七个主要 endpoint 域的 MIPE（最小实际重要效应），随后才可在不读取算法效果的条件下重现 identity-blind 功效计算并选择最小满足功效的 B。

需要明确的 MIPE 是：D1 几何均值比和 P95 比、D2 网格读取工作比、D3 动态分配的 log1p 对比及原始字节解释、D4 持久状态的 log1p 对比及原始字节解释、D5 对 log2(N) 的斜率差、D6 对 log2(F) 的斜率差、D7 对 log2(G^2) 的斜率差。所有方向均为 lower-is-better。

此外，需要决定 S5 movement-transfer sentinel 是明确省略，还是指定一个执行前固定的精确 subset。

在这些科学输入获得明确授权前，不会冻结 B、正式 ST 合同或正式 schedule，也不会执行第 9 项。迁移包仍为 `DORMANT_SEALED_FOR_LATER_REACTIVATION`，且未构建任何包、staging/test root、安装器/credential 副本或 ZIP。
