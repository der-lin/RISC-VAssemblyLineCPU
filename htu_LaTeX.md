# htu_LaTeX 快速查询笔记

> 适用场景：在 Windows + TeX Live + VS Code + LaTeX Workshop 中编辑老师给出的武汉大学实验报告 LaTeX 模板。  
> 当前模板建议使用 **XeLaTeX** 编译；`main.tex` 是主文件，`pages/` 文件夹中放正文各章节。

---

## 1. 项目结构应该怎么看

老师模板大致结构如下：

```text
TeXLatex/
├─ main.tex                 # 主文件，编译它
├─ WHUExperiment.cls        # 模板类文件，不要随便改
├─ pages/
│  ├─ frontmatter.tex       # 摘要等前置内容
│  ├─ chapter1.tex          # 第 1 章正文
│  ├─ chapter2.tex
│  ├─ chapter3.tex
│  ├─ chapter4.tex
│  ├─ chapter5.tex
│  ├─ chapter6.tex
│  └─ backmatter.tex        # 结论等
├─ whu.pdf
├─ whulogo.pdf
└─ figures/                 # 建议自己新建，用来放实验图片
```

核心原则：

```text
无论你正在编辑 pages/chapter1.tex 还是 pages/chapter5.tex，最终都应该编译 main.tex。
```

因为 `main.tex` 中会统一加载：

```latex
\input{pages/frontmatter}
\input{pages/chapter1}
\input{pages/chapter2}
\input{pages/chapter3}
\input{pages/chapter4}
\input{pages/chapter5}
\input{pages/chapter6}
\input{pages/backmatter}
```

---

## 2. VS Code 中的常用快捷键

### 2.1 选择编译方案

第一次建议手动选择一次：

```text
Ctrl + Shift + P
→ LaTeX Workshop: Build with recipe
→ latexmk with XeLaTeX
```

只要日志中出现：

```text
latexmk ... -xelatex ...
```

就说明正在用 XeLaTeX 编译。

### 2.2 一键编译

以后可以直接使用：

```text
Ctrl + Alt + B
```

它会调用 LaTeX Workshop 的默认编译方案。

### 2.3 预览 PDF

```text
Ctrl + Alt + V
```

或者：

```text
Ctrl + Shift + P
→ LaTeX Workshop: View LaTeX PDF
```

### 2.4 清理辅助文件

当出现“之前失败过但现在不重新编译”“Nothing to do”“up-to-date 但仍报错”时，可以清理：

```text
Ctrl + Shift + P
→ LaTeX Workshop: Clean up auxiliary files
```

也可以手动删除这些文件：

```text
main.aux
main.log
main.fdb_latexmk
main.fls
main.out
main.toc
main.synctex.gz
```

---

## 3. 确保 pages 里的章节知道主文件是谁

如果你正在编辑 `pages/chapter1.tex`，LaTeX Workshop 有时可能不知道应该编译上一级的 `main.tex`。

建议在每个 `pages/chapter*.tex` 的第一行加：

```latex
% !TEX root = ../main.tex
```

例如：

```latex
% !TEX root = ../main.tex

\chapter{实验目的与要求}

这里开始写正文。
```

这样即使你当前打开的是 `chapter1.tex`，按 `Ctrl + Alt + B` 也会编译 `main.tex`。

---

## 4. 如何在想要的位置插入正文内容

### 4.1 插入章节

```latex
\chapter{实验目的}
```

### 4.2 插入小节

```latex
\section{实验环境}
```

### 4.3 插入更小一级标题

```latex
\subsection{ModelSim 仿真环境}
```

### 4.4 插入普通段落

直接写中文即可：

```latex
本实验基于 SystemVerilog 实现了一个五级流水线 RISC-V CPU，并通过仿真程序对其正确性进行验证。
```

注意：LaTeX 中**空一行**表示换段。

```latex
这是第一段。

这是第二段。
```

---

## 5. 如何插入图片

### 5.1 推荐图片文件夹

建议在 `main.tex` 同级目录下新建：

```text
figures/
```

然后把图片放进去，例如：

```text
figures/pipeline_structure.png
figures/modelsim_wave.png
figures/register_result.png
```

### 5.2 推荐图片格式

使用 XeLaTeX 时，优先使用：

```text
.png
.jpg
.pdf
```

不建议新手直接使用：

```text
.eps
```

`.eps` 有时需要额外转换，容易报错。

### 5.3 最常用的插图代码

在需要插图的位置写：

```latex
\begin{figure}[htbp]
    \centering
    \includegraphics[width=0.85\textwidth]{figures/pipeline_structure.png}
    \caption{五级流水线 CPU 总体结构图}
    \label{fig:pipeline-structure}
\end{figure}
```

含义：

```text
figure       表示这是一个浮动图片环境
[htbp]       表示 LaTeX 可以尝试放在当前位置、页顶、页底或单独浮动页
\centering   图片居中
width=0.85\textwidth  图片宽度为正文宽度的 85%
\caption{}   图片标题
\label{}     图片标签，便于正文引用
```

正文中引用图片：

```latex
如图~\ref{fig:pipeline-structure} 所示，CPU 采用经典五级流水线结构。
```

### 5.4 图片路径的关键规则

即使插图代码写在：

```text
pages/chapter3.tex
```

图片路径通常也应该按 `main.tex` 所在目录来写：

```latex
\includegraphics[width=0.85\textwidth]{figures/modelsim_wave.png}
```

不要写成：

```latex
\includegraphics{../figures/modelsim_wave.png}
```

除非你的模板或编译方式非常特殊。一般情况下，主文件是 `main.tex`，路径就按 `main.tex` 所在目录计算。

### 5.5 图片文件名建议

尽量使用英文、数字、下划线，不要用中文、空格、特殊符号。

推荐：

```text
modelsim_wave_load_use.png
pipeline_forwarding.png
branch_flush_result.png
```

不推荐：

```text
流水线 波形截图 1.png
第3章-结果(最终版).png
```

### 5.6 想让图片尽量出现在当前位置

一般用：

```latex
\begin{figure}[htbp]
```

如果你强烈希望图片固定在当前位置，可以用：

```latex
\begin{figure}[H]
```

老师模板的 `WHUExperiment.cls` 已经加载了 `float` 宏包，所以通常可以使用 `[H]`。

示例：

```latex
\begin{figure}[H]
    \centering
    \includegraphics[width=0.9\textwidth]{figures/modelsim_wave.png}
    \caption{ModelSim 仿真波形结果}
    \label{fig:modelsim-wave}
\end{figure}
```

但注意：大量使用 `[H]` 可能导致页面留白不好看。正式报告中一般优先用 `[htbp]`。

### 5.7 插入两张并排图片

```latex
\begin{figure}[htbp]
    \centering
    \begin{subfigure}{0.48\textwidth}
        \centering
        \includegraphics[width=\textwidth]{figures/before.png}
        \caption{修改前}
        \label{fig:before}
    \end{subfigure}
    \hfill
    \begin{subfigure}{0.48\textwidth}
        \centering
        \includegraphics[width=\textwidth]{figures/after.png}
        \caption{修改后}
        \label{fig:after}
    \end{subfigure}
    \caption{修改前后仿真结果对比}
    \label{fig:compare}
\end{figure}
```

老师模板已经加载了 `subcaption` 宏包，因此可以使用 `subfigure`。

---

## 6. 如何插入公式

### 6.1 行内公式

```latex
流水线 CPI 的理想值接近 $1$。
```

### 6.2 单独居中的公式

```latex
\[
CPI = \frac{\text{总时钟周期数}}{\text{执行指令条数}}
\]
```

### 6.3 带编号公式

```latex
\begin{equation}
CPI = \frac{\text{总时钟周期数}}{\text{执行指令条数}}
\label{eq:cpi}
\end{equation}
```

正文引用：

```latex
由式~\ref{eq:cpi} 可知，流水线性能与总周期数和指令条数有关。
```

---

## 7. 如何插入代码

老师模板已经加载了 `listings` 宏包。

### 7.1 插入短代码

```latex
\begin{lstlisting}[language=Verilog, caption={PC 更新逻辑示例}, label={lst:pc-update}]
always_ff @(posedge clk) begin
    if (rst) begin
        pc <= 32'b0;
    end else if (!stall) begin
        pc <= next_pc;
    end
end
\end{lstlisting}
```

### 7.2 插入汇编代码

如果没有专门的 RISC-V 语言高亮，可以先不写 `language`：

```latex
\begin{lstlisting}[caption={RISC-V 测试程序片段}, label={lst:riscv-test}]
addi x1, x0, 10
addi x2, x0, 20
add  x3, x1, x2
sw   x3, 0(x0)
\end{lstlisting}
```

### 7.3 插入文件路径或命令

```latex
\begin{lstlisting}[caption={终端编译命令}]
latexmk -xelatex main.tex
\end{lstlisting}
```

---

## 8. 如何插入表格

简单表格：

```latex
\begin{table}[htbp]
    \centering
    \caption{主要模块功能说明}
    \label{tab:modules}
    \begin{tabular}{lll}
        \toprule
        模块 & 文件 & 功能 \\
        \midrule
        IF & ifetch.sv & 取指与 PC 更新 \\
        ID & decode.sv & 指令译码与寄存器读取 \\
        EX & execute.sv & ALU 运算与分支判断 \\
        MEM & memory.sv & 数据存储器访问 \\
        WB & writeback.sv & 写回寄存器堆 \\
        \bottomrule
    \end{tabular}
\end{table}
```

老师模板已经加载了 `booktabs`，可以使用 `\toprule`、`\midrule`、`\bottomrule`。

---

## 9. 终端中手动编译的方法

如果 VS Code 出问题，可以在 `main.tex` 所在目录打开终端。

### 9.1 进入目录

```bat
cd /d "E:\WHU\Kinding_Plan\RISC-VAssemblyLineCPU\FromTeacher\TeXLatex"
```

### 9.2 推荐编译命令

```bat
latexmk -xelatex main.tex
```

### 9.3 清理后重新编译

```bat
latexmk -C main.tex
latexmk -xelatex main.tex
```

### 9.4 简单直接的编译方式

```bat
xelatex main.tex
xelatex main.tex
```

如果有目录、引用、交叉引用，通常至少编译两次。

---

## 10. 常见问题速查

### 10.1 报错：不支持 pdfLaTeX

现象：日志里出现 `pdflatex`。

解决：使用 XeLaTeX：

```text
Ctrl + Shift + P
→ LaTeX Workshop: Build with recipe
→ latexmk with XeLaTeX
```

### 10.2 图片找不到

检查：

```text
1. 图片是否真的在 figures/ 文件夹中
2. 文件名是否完全一致
3. 后缀是否正确：.png / .jpg / .pdf
4. 路径是否按 main.tex 所在目录来写
```

### 10.3 中文乱码

检查：

```text
1. 是否使用 XeLaTeX
2. 文件编码是否是 UTF-8
3. 是否使用了 ctex 类或中文模板
```

### 10.4 PDF 不更新

可能是辅助文件导致的。清理：

```text
Ctrl + Shift + P
→ LaTeX Workshop: Clean up auxiliary files
```

或终端：

```bat
latexmk -C main.tex
latexmk -xelatex main.tex
```

### 10.5 正在编辑 chapter1.tex，但编译失败

在 `chapter1.tex` 第一行加入：

```latex
% !TEX root = ../main.tex
```

然后重新编译。

---

## 11. 写实验报告时的建议目录

如果当前只完成 RISC-V Pipeline 主体部分，可以先这样组织：

```text
chapter1：实验目的与任务说明
chapter2：实验环境与工具链
chapter3：CPU 总体设计
chapter4：关键模块与流水线机制详细设计
chapter5：仿真测试与结果分析
chapter6：实验总结与后续工作
backmatter：结论
```

暂时不写或仅在“后续工作”中简要说明：

```text
1. 自己编写 RISC-V 汇编应用程序并在自研 CPU 上运行
2. 中断、计数器中断、syscall、VGA/PS2 等外设接口扩展
```

---

## 12. 最推荐的日常使用流程

```text
1. 打开 VS Code
2. 打开整个 TeXLatex 文件夹，而不是只打开单个 tex 文件
3. 编辑 pages/chapter*.tex
4. Ctrl + Alt + B 编译
5. Ctrl + Alt + V 查看 PDF
6. 如果不更新，Clean up auxiliary files 后重新编译
```

---

## 13. 插图建议：RISC-V Pipeline 实验报告常用图片

建议准备这些图片：

```text
1. CPU 总体结构图
2. 五级流水线数据通路图
3. IF/ID、ID/EX、EX/MEM、MEM/WB 流水寄存器设计图
4. 数据前递机制示意图
5. load-use 暂停波形图
6. 分支跳转/flush 波形图
7. 排序程序或测试程序运行后的寄存器结果图
8. 数据存储器最终结果截图
9. 指令覆盖或测试程序说明图
10. ModelSim 仿真成功波形截图
```

图片不要堆砌，最好每张图下面都有解释：

```latex
图中可以看出，当 load 指令后继指令立即使用其结果时，控制模块产生 stall 信号，使 IF/ID 寄存器保持不变，同时向 ID/EX 注入气泡，从而避免读取尚未写回的数据。
```

