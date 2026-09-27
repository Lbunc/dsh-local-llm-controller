# 能力题库 · 困难档

需要区分度时使用。覆盖近期竞赛数学、研究生科学、叙事多步推理、约束逻辑、长上下文与近期编程。
**上下文按 64K 设计**，把「长思考」与「长上下文」同时放进预算内。

## 使用约束

- **本题库是冻结资产**：`10q_hard.json` 是机器可读的权威副本，**自包含**（prompt / 官方答案键 / 判分规格 / 代码题用例）。
  跑题与判分**只依赖它，不需要联网**，也不要依赖任何源数据仓库。
- **不得增删改题、不得临时自出题**。题目与官方答案键均取自公开基准仓库（见下方来源表）。
- 采样固定：`--temp 0.6 --top-k 20 --top-p 0.95 --min-p 0.0 --repeat-penalty 1 --presence-penalty 0`。
- **思考预算**：`--reasoning-budget = n_ctx / 2`（硬规则，见 [`reference/05-reasoning-budget.md`](../reference/05-reasoning-budget.md)）。
- **`max_tokens`**：按 `rb + 答案余量` 计算，并夹取到 `prompt_tokens + max_tokens ≤ n_ctx`。
  本题库已逐题写定（见下表）；长 prompt 的题必须先量真实 token 数。
- **截断语义**：`finish=length` 且判分不通过 → 记「未产出」，从分母剔除、**不得判 0**，重跑而不是记错。
- **判分必须程序化**；**先过区分度门**（见 [`reference/09-capability-bank.md`](../reference/09-capability-bank.md)）。
- 跑题与判分脚本：[`scripts/run_bank.ps1`](../scripts/run_bank.ps1)、[`scripts/grade_bank.py`](../scripts/grade_bank.py)、
  [`scripts/recover_bank_json.py`](../scripts/recover_bank_json.py)、[`scripts/verify_bank_budget.ps1`](../scripts/verify_bank_budget.ps1)。

## 本题库参数

| 项 | 值 |
|---|---|
| 题库 JSON | `10q_hard.json` |
| 条目数 | 10 |
| `n_ctx` | 65536 |
| `reasoning_budget` | 32768 |
| 选项重排种子 | 20260214 |

## 来源与题型

| qid | 轴 | 来源 | 日期 | 类型 | 官方键 | `max_tokens` |
|---|---|---|---|---|---|---|

| Q1 | 竞赛数学 | AIME | 2026-02 | int | 70 | 40960 |
| Q2 | 竞赛数学 | AIME | 2026-02 | int | 39 | 40960 |
| Q3 | 竞赛数学 | HMMT | 2025-11 | int | 5 | 40960 |
| Q4 | 竞赛数学 | AIME | 2026-02 | int | 396 | 40960 |
| Q5 | 研究生科学 | GPQA-Diamond | 2023-11 | mc | 10^-4 eV | 36864 |
| Q6 | 研究生科学 | GPQA-Diamond | 2023-11 | mc | 11 | 36864 |
| Q7 | 叙事多步推理 | MuSR | 2023-10 | mc | Earth | 36864 |
| Q8 | 约束逻辑 | ZebraLogic | 2024-06 | mc | romance | 36864 |
| Q9 | 长上下文多文档 | LongBench-v2 | 2024-12 | mc | B | 19456 |
| Q10 | 近期编程 | LiveCodeBench | 2025-01-25 | lcb_ref | 3 public tests | 40960 |

## 判分规格（`gtype` → 规则）

| gtype | 规则 |
|---|---|
| `mc` | 取「最后一次显式结论」优先，退回最后一个 `(X)`、最后独立字母；与官方字母键比对 |
| `yesno` | 取最后一个 yes / no |
| `int` | 取最后一个 `\boxed{{}}` 内的整数，退回最后一个整数；与官方整数键精确相等 |
| `words` | 目标词按序出现在回答词序列中 |
| `sym` | 取最后一段括号串 |
| `grid` | 逐行精确匹配 |
| `code` | 拆代码块 → 每块单独跑官方测试 → 取最高 |
| `lcb_ref` | 抽代码块 → 逐条跑官方/参考用例比对 stdin/stdout → 全过才算对 |

> 选项已用固定种子重排（防位置偏置），字母键随题库 JSON 一并记录。
> 逐题的来源、官方键与**换题记录**见每题的 `note` 字段。

---


## Q1 · AIME 2026 Problem 4

- 来源：**AIME**（2026-02）
- 轴：竞赛数学　类型：`int`
- 官方答案键：`70`
- 判分键（重排后）：`70`
- `max_tokens`：**40960**
- 说明 / 来源记录：最终答案必须是整数，判分取 \boxed{} 内整数（退化取最后一个整数）

### Prompt

```text
Find the number of integers less than or equal to 100 that are equal to $a+b+ab$ for some choice of distinct positive integers a and b.

Solve the problem. Reason carefully and show your work, then state the final answer as \boxed{...} using an integer.
```

---

## Q2 · AIME 2026 Problem 13

- 来源：**AIME**（2026-02）
- 轴：竞赛数学　类型：`int`
- 官方答案键：`39`
- 判分键（重排后）：`39`
- `max_tokens`：**40960**
- 说明 / 来源记录：最终答案必须是整数，判分取 \boxed{} 内整数（退化取最后一个整数）

### Prompt

```text
For each positive integer $r$ less than $502,$ define
\[
S_r=\sum_{m\ge 0}\dbinom{10000}{502n+r},
\]
where $\binom{10000}{n}$ is defined to be $0$ when $n>10000.$ That is, $S_r$ is the sum of all binomial coefficients of the form $\binom{10000}{k}$ for which $0\le k\le 10000$ and $k-r$ is a multiple of $502.$ Find the number of integers in the list $S_0,S_1,\dots,S_{501}$ that are multiples of the prime number $503.$

Solve the problem. Reason carefully and show your work, then state the final answer as \boxed{...} using an integer.
```

---

## Q3 · HMMT November 2025 Problem 12

- 来源：**HMMT**（2025-11）
- 轴：竞赛数学　类型：`int`
- 官方答案键：`5`
- 判分键（重排后）：`5`
- `max_tokens`：**40960**
- 说明 / 来源记录：最终答案必须是整数，判分取 \boxed{} 内整数（退化取最后一个整数）

### Prompt

```text
Uranus has $29$ known moons. Each moon is blue, icy, or large, though some moons may have several of these characteristics. There are $10$ moons which are blue but not icy, $8$ moons which are icy but not large, and $6$ moons which are large but not blue. Compute the number of moons which are simultaneously blue, icy, and large.

Solve the problem. Reason carefully and show your work, then state the final answer as \boxed{...} using an integer.
```

---

## Q4 · AIME 2026 Problem 7

- 来源：**AIME**（2026-02）
- 轴：竞赛数学　类型：`int`
- 官方答案键：`396`
- 判分键（重排后）：`396`
- `max_tokens`：**40960**
- 说明 / 来源记录：最终答案必须是整数，判分取 \boxed{} 内整数。★换题记录：原 Q4 = HMMT Feb 2026 #33（MathArena），其题面「把任一数替换成当前最大与最小的正差」保持数字个数(2026)与总和(2053351)不变，而 2026 ∤ 2053351 →「所有数相等」无解，故该条目的答案 3037 与题面不符（源数据缺陷），已弃用替换。本题键 396 经【全排列穷举】+ 两个独立镜像（MathArena / math-ai/aime26）三方一致。

### Prompt

```text
Find the number of functions $\pi$ mapping the set $A =\{1,2,3,4,5,6\}$ onto $A$ such that for every $a \in A,$
\[
\pi(\pi(\pi(\pi(\pi(\pi(a)))))) = a.
\]

Solve the problem. Reason carefully and show your work, then state the final answer as \boxed{...} using an integer.
```

---

## Q5 · GPQA-Diamond (Physics, general)

- 来源：**GPQA-Diamond**（2023-11）
- 轴：研究生科学　类型：`mc`
- 官方答案键：`10^-4 eV`
- 判分键（重排后）：`B`
- `max_tokens`：**36864**
- 说明 / 来源记录：官方答案：10^-4 eV（选项已用固定种子 20260214 重排）

### Prompt

```text
Two quantum states with energies E1 and E2 have a lifetime of 10^-9 sec and 10^-8 sec, respectively. We want to clearly distinguish these two energy levels. Which one of the following options could be their energy difference so that they can be clearly resolved?

A. 10^-8 eV
B. 10^-4 eV
C. 10^-11 eV
D. 10^-9 eV

Answer with the letter of the correct option. Think it through, then end your reply with exactly: The answer is (X).
```

---

## Q6 · GPQA-Diamond (Organic Chemistry)

- 来源：**GPQA-Diamond**（2023-11）
- 轴：研究生科学　类型：`mc`
- 官方答案键：`11`
- 判分键（重排后）：`B`
- `max_tokens`：**36864**
- 说明 / 来源记录：官方答案：11（选项已用固定种子 20260214 重排）

### Prompt

```text
trans-cinnamaldehyde was treated with methylmagnesium bromide, forming product 1.

1 was treated with pyridinium chlorochromate, forming product 2.

3 was treated with (dimethyl(oxo)-l6-sulfaneylidene)methane in DMSO at elevated temperature, forming product 3.

how many carbon atoms are there in product 3?

A. 10
B. 11
C. 14
D. 12

Answer with the letter of the correct option. Think it through, then end your reply with exactly: The answer is (X).
```

---

## Q7 · MuSR object_placements (longest narrative)

- 来源：**MuSR**（2023-10）
- 轴：叙事多步推理　类型：`mc`
- 官方答案键：`Earth`
- 判分键（重排后）：`C`
- `max_tokens`：**36864**
- 说明 / 来源记录：官方答案：Earth（选项固定种子重排）

### Prompt

```text
In the mid of the day, the archaeologist Martha, fervently trying to finish her excavation work at the site, felt the ominous presence of upcoming rains. Motivated by her cravings for discoveries, her eyes were distracted by the precious ancient coin, discovered with care, held firmly in the grasp of earth. Her assistant Tom, just a laborer with an ambition of a career in archeology, worked diligently at the marked areas, covertly observing Martha’s every movement. On the other hand, Jenny, the recent graduate and enthusiastic volunteer, was eager to aid in the excavation in any way she could.

The magnifying glass was at reach, inside the well-equipped excavation kit, radiant under the scorching sun, vital for Martha’s meticulous inspection of any artifact. A collective understanding among them about the location of each tool was inherent. After all, in the vast realm of an excavation site, chaos was not spared a location.

Quickly, Martha rushed to the well-equipped excavation kit, snatching the magnifying glass and moving it over to the inspection area. The glass glistened under the sun as she handled it with a sense of urgency, her eyes eager to delve into the secrets the ancient coin held within. Meanwhile, Tom found himself drawn to an unearthed piece of pottery, a treasured find from the burial of the sands. Paying intense attention, he studied the object in his hands, both unfamiliar and uncanny. It was remarkably similar to a specimen he had seen in a textbook during his aspirations for a more academic role in archeology.

In tandem, Jenny keenly observed Martha, standing a little off to the side, helping when directed, her eyes darting between Martha's skilled handling of the artifacts and Tom's steady digging. The underway operation was a captivating orchestration of trowels, brushes, and screens, capturing not just their interest but their collective dedication to the archaeological process.

Handling the coin delicately, Tom passed it to the inspection area with a sense of apprehension, hoping not to damage the piece of antiquity. Upon moving it there, his gaze stumbled upon the magnifying glass, carelessly placed right beside the coin. Amid the day's work at the excavation site, the coordinated hustle of the team was a sight to behold. Martha found herself assisting Tom in his meticulous digging, the rhythm of their collaboration undisturbed even in the face of looming weather. Each scoop of the earth bore the potential of concealed history, and Tom, driven by his aspirations, savored every moment under Martha's tutelage.

While they worked, Jenny busied herself too. A role often overlooked by spectators of the archeological process, she was tasked with securing the excavation site from the upcoming brutal winds. Together with Martha, she was setting up a windbreaker at a spot quite a ways from Tom. The positioning was strategic, as the key was to protect unearthed finds from the wrestling winds without hindering ongoing excavations. 

Tom continued his endeavor, engrossed in his work. Guided by Martha's seasoned hand and watchful eyes, he held the responsibility of navigating the layers of historic dust with utmost precision. It was a balancing act of digging swiftly and carefully, all the while keeping an eye on the unfolding mysteries that lay beneath. 

Every movement counted, every breath held a sense of anticipation. The rhythm of the excavation flowed in smooth patterns, the story of times long gone slowly revealing itself through the sandy canvas beneath their feet.

Post Martha's inspection, Jenny carefully picked up the magnifying glass and moved it back to its designated pocket in the excavation kit; preserving it safe and sound for future use. In the prime of the sun, the looming threat of rain hung heavily in the air. Martha, the archaeologist, found it difficult to shift her focus from the hidden relics which lay beneath the ground. Offering a helping hand, laborer Tom dug into the marked areas while stealing glances at Martha, planning his future steps in the world of archeology. On the sidelines, fresh graduate, Jenny, observed the unfolding fervor with an unquenchable thirst for knowledge.

An indispensable accessory was housed within the excavation kit, untouched under the glaring sun, awaited movement of Martha's hand for further evaluation of the precious artifacts. Their synergy was crucial in navigating the intricate world of excavation. After all, disorder had no place amidst the sands and relics.

Martha sought the unseen accessory with a sense of urgency. Swiftly, she moved it over to the inspection area; the accessory sparkled under the fervid sunshine, looking ready for the duties it was to perform. Concurrently, a small artifact, hidden beneath the layers of sand, caught Tom's attention. To him, the piece looked oddly familiar, he had seen something similar in the textbooks during his early days in archaeology.

In the meantime, Jenny maintained a close watch on Martha, ready to help wherever needed. The tools of labor moved rhythmically across the site, each serving a purpose in the ongoing process of archaeological excavation.

Tom handled the newly discovered artifact with caution, understanding its fragility and the historical importance it held. He presented it to Martha for further inspection. Seeing the important accessory resting beside, brought forth a realization of the coordinated nature of the team's efforts. Under Martha's guidance, he continued on his voyage of the buried past. Every scoop of soil was a step into the depths of history, leaving him all the more absorbed in his pursuit of archeology.

While Tom was lost in his world, Jenny was tasked with an important responsibility, that of protecting the excavation site from the predicted winds. Working in unity with Martha, she erected a windbreaker at a safe distance from Tom's ongoing excavation. The effort was directed towards impeding the winds from affecting the unearthed artifacts but not hindering their efforts.

Tom, under Martha's watchful eyes, continued to decipher the concealed stories within the layers of earthly time. The exercise demanded the finesse of swift yet careful investigation, all the while unveiling the hidden chapters of history.

Each movement held significance, each revelation fostered a sense of accomplishment. As they moved the sands, time seemed to rewind, piecing together the long-forgotten narratives of human civilization right beneath their feet.

At the end of her inspection, Jenny carefully placed back the accessory into its pocket in the kit, ensuring its safekeeping for further adventures. The excavations were suspended for the day, as the team wrapped up, looking forward to the newer discoveries that awaited them. As the light fell and the winds hushed, the site turned into a silent theatre, routing the dreams of secrets soon to be unraveled.

Which location is the most likely place Jenny would look to find the ancient coin given the story?

A. Inspection area
B. Excavation kit
C. Earth

Answer with the letter of the correct option. Think it through, then end your reply with exactly: The answer is (X).
```

---

## Q8 · ZebraLogic 6x6 mc (lgp-test-6x6-0#mc-1)

- 来源：**ZebraLogic**（2024-06）
- 轴：约束逻辑　类型：`mc`
- 官方答案键：`romance`
- 判分键（重排后）：`C`
- `max_tokens`：**36864**
- 说明 / 来源记录：官方答案：romance；choices 原始类型=list

### Prompt

```text
There are 6 houses, numbered 1 to 6 from left to right, as seen from across the street. Each house is occupied by a different person. Each house has a unique attribute for each of the following characteristics:
 - Each person has a unique name: `Peter`, `Eric`, `Alice`, `Bob`, `Arnold`, `Carol`
 - People have unique favorite book genres: `mystery`, `fantasy`, `romance`, `historical fiction`, `science fiction`, `biography`
 - Everyone has a favorite smoothie: `cherry`, `desert`, `lime`, `watermelon`, `blueberry`, `dragonfruit`
 - The people keep unique animals: `fish`, `rabbit`, `bird`, `cat`, `horse`, `dog`
 - People have unique favorite music genres: `classical`, `hip hop`, `country`, `jazz`, `rock`, `pop`
 - Everyone has a unique favorite cigar: `prince`, `dunhill`, `blends`, `pall mall`, `blue master`, `yellow monster`

## Clues:
1. The person who smokes many unique blends is the person who loves fantasy books.
2. The person who loves biography books is the Desert smoothie lover.
3. There are two houses between the person who loves pop music and the person who loves country music.
4. The rabbit owner is in the third house.
5. Arnold is the bird keeper.
6. The person who loves country music is in the fifth house.
7. The person who loves mystery books is not in the first house.
8. The person who drinks Lime smoothies is not in the third house.
9. The fish enthusiast is somewhere to the right of the person who loves rock music.
10. The Prince smoker is somewhere to the left of the person who likes Cherry smoothies.
11. Bob is the cat lover.
12. Eric is the person who likes Cherry smoothies.
13. The person who smokes Yellow Monster is in the sixth house.
14. The Prince smoker is the Dragonfruit smoothie lover.
15. Carol is directly left of Arnold.
16. The person who smokes Blue Master is directly left of the person who loves classical music.
17. The person who loves classical music is the person who loves historical fiction books.
18. The Dunhill smoker and the person who loves science fiction books are next to each other.
19. The person who keeps horses is directly left of Peter.
20. The Watermelon smoothie lover is the cat lover.
21. The person who smokes many unique blends is directly left of the person who loves jazz music.
22. The cat lover is in the first house.
23. The Desert smoothie lover is the person who loves jazz music.
24. The person who drinks Lime smoothies is directly left of the fish enthusiast.
25. The person who smokes Blue Master is not in the fifth house.

What is BookGenre of the person who lives in House 1?

A. science fiction
B. historical fiction
C. romance
D. mystery
E. fantasy
F. biography

Answer with the letter of the correct option. Think it through, then end your reply with exactly: The answer is (X).
```

---

## Q9 · LongBench-v2 Multi-Document QA/Academic (136143 chars)

- 来源：**LongBench-v2**（2024-12）
- 轴：长上下文多文档　类型：`mc`
- 官方答案键：`B`
- 判分键（重排后）：`B`
- `max_tokens`：**19456**
- 说明 / 来源记录：官方答案：B（选项固定种子重排）；上下文 136143 字符，目标 ~30k tokens

### Prompt

```text
Read the following documents carefully, then answer the question.

<documents>
3D Gaussian Splatting for Real-Time Radiance Field Rendering
Ground Truth
InstantNGP (9.2  fps) 
Plenoxels (8.2 fps) 
Train: 7min, PSNR: 22.1
Train: 26min, PSNR: 21.9
Mip-NeRF360 (0.071 fps) 
Train: 48 h, PSNR: 24.3
Ours (135  fps) 
Train: 6 min, PSNR: 23.6
Ours (93  fps) 
Train: 51min, PSNR: 25.2
Fig. 1. Our method achieves real-time rendering of radiance fields with quality that equals the previous method with the best quality [Barron et al. 2022],
while only requiring optimization times competitive with the fastest previous methods [Fridovich-Keil and Yu et al. 2022; Müller et al. 2022]. Key to this
performance is a novel 3D Gaussian scene representation coupled with a real-time differentiable renderer, which offers significant speedup to both scene
optimization and novel view synthesis. Note that for comparable training times to InstantNGP [Müller et al. 2022], we achieve similar quality to theirs; while
this is the maximum quality they reach, by training for 51min we achieve state-of-the-art quality, even slightly better than Mip-NeRF360 [Barron et al. 2022].
Radiance Field methods have recently revolutionized novel-view synthesis
of scenes captured with multiple photos or videos. However, achieving high
visual quality still requires neural networks that are costly to train and ren-
der, while recent faster methods inevitably trade off speed for quality. For
unbounded and complete scenes (rather than isolated objects) and 1080p
resolution rendering, no current method can achieve real-time display rates.
We introduce three key elements that allow us to achieve state-of-the-art
visual quality while maintaining competitive training times and importantly
allow high-quality real-time (≥30 fps) novel-view synthesis at 1080p resolu-
tion. First, starting from sparse points produced during camera calibration,
we represent the scene with 3D Gaussians that preserve desirable proper-
ties of continuous volumetric radiance fields for scene optimization while
avoiding unnecessary computation in empty space; Second, we perform
interleaved optimization/density control of the 3D Gaussians, notably opti-
mizing anisotropic covariance to achieve an accurate representation of the
scene; Third, we develop a fast visibility-aware rendering algorithm that
supports anisotropic splatting and both accelerates training and allows real-
time rendering. We demonstrate state-of-the-art visual quality and real-time
rendering on several established datasets.
CCS Concepts: • Computing methodologies →Rendering; Point-based
models; Rasterization; Machine learning approaches.
∗Both authors contributed equally to the paper.
Authors’ addresses: Bernhard Kerbl, bernhard.kerbl@inria.fr, Inria, Université Côte
d’Azur, France; Georgios Kopanas, georgios.kopanas@inria.fr, Inria, Université Côte
d’Azur, France; Thomas Leimkühler, thomas.leimkuehler@mpi-inf.mpg.de, Max-
Planck-Institut für Informatik, Germany; George Drettakis, george.drettakis@inria.fr,
Inria, Université Côte d’Azur, France.
Publication rights licensed to ACM. ACM acknowledges that this contribution was
authored or co-authored by an employee, contractor or affiliate of a national govern-
ment. As such, the Government retains a nonexclusive, royalty-free right to publish or
reproduce this article, or to allow others to do so, for Government purposes only.
© 2018 Copyright held by the owner/author(s). Publication rights licensed to ACM.
0730-0301/2018/0-ART0 $15.00
https://doi.org/XXXXXXX.XXXXXXX
Additional Key Words and Phrases: novel view synthesis, radiance fields, 3D
gaussians, real-time rendering
ACM Reference Format:
Bernhard Kerbl, Georgios Kopanas, Thomas Leimkühler, and George Dret-
takis. 2018. 3D Gaussian Splatting for Real-Time Radiance Field Rendering.
ACM Trans. Graph. 0, 0, Article 0 ( 2018), 14 pages. https://doi.org/XXXXXXX.
XXXXXXX
1
INTRODUCTION
Meshes and points are the most common 3D scene representations
because they are explicit and are a good fit for fast GPU/CUDA-based
rasterization. In contrast, recent Neural Radiance Field (NeRF) meth-
ods build on continuous scene representations, typically optimizing
a Multi-Layer Perceptron (MLP) using volumetric ray-marching for
novel-view synthesis of captured scenes. Similarly, the most efficient
radiance field solutions to date build on continuous representations
by interpolating values stored in, e.g., voxel [Fridovich-Keil and Yu
et al. 2022] or hash [Müller et al. 2022] grids or points [Xu et al. 2022].
While the continuous nature of these methods helps optimization,
the stochastic sampling required for rendering is costly and can
result in noise. We introduce a new approach that combines the best
of both worlds: our 3D Gaussian representation allows optimization
with state-of-the-art (SOTA) visual quality and competitive training
times, while our tile-based splatting solution ensures real-time ren-
dering at SOTA quality for 1080p resolution on several previously
published datasets [Barron et al. 2022; Hedman et al. 2018; Knapitsch
et al. 2017] (see Fig. 1).
Our goal is to allow real-time rendering for scenes captured with
multiple photos, and create the representations with optimization
times as fast as the most efficient previous methods for typical
real scenes. Recent methods achieve fast training [Fridovich-Keil
ACM Trans. Graph., Vol. 42, No. 4, Article . Publication date: August 2023.


2
•
Bernhard Kerbl, Georgios Kopanas, Thomas Leimkühler, and George Drettakis
and Yu et al. 2022; Müller et al. 2022], but struggle to achieve the
visual quality obtained by the current SOTA NeRF methods, i.e.,
Mip-NeRF360 [Barron et al. 2022], which requires up to 48 hours of
training time. The fast – but lower-quality – radiance field methods
can achieve interactive rendering times depending on the scene
(10-15 frames per second), but fall short of real-time rendering at
high resolution.
Our solution builds on three main components. We first intro-
duce 3D Gaussians as a flexible and expressive scene representation.
We start with the same input as previous NeRF-like methods, i.e.,
cameras calibrated with Structure-from-Motion (SfM) [Snavely et al.
2006] and initialize the set of 3D Gaussians with the sparse point
cloud produced for free as part of the SfM process. In contrast to
most point-based solutions that require Multi-View Stereo (MVS)
data [Aliev et al. 2020; Kopanas et al. 2021; Rückert et al. 2022], we
achieve high-quality results with only SfM points as input. Note
that for the NeRF-synthetic dataset, our method achieves high qual-
ity even with random initialization. We show that 3D Gaussians
are an excellent choice, since they are a differentiable volumetric
representation, but they can also be rasterized very efficiently by
projecting them to 2D, and applying standard 𝛼-blending, using an
equivalent image formation model as NeRF. The second component
of our method is optimization of the properties of the 3D Gaussians
– 3D position, opacity 𝛼, anisotropic covariance, and spherical har-
monic (SH) coefficients – interleaved with adaptive density control
steps, where we add and occasionally remove 3D Gaussians during
optimization. The optimization procedure produces a reasonably
compact, unstructured, and precise representation of the scene (1-5
million Gaussians for all scenes tested). The third and final element
of our method is our real-time rendering solution that uses fast GPU
sorting algorithms and is inspired by tile-based rasterization, fol-
lowing recent work [Lassner and Zollhofer 2021]. However, thanks
to our 3D Gaussian representation, we can perform anisotropic
splatting that respects visibility ordering – thanks to sorting and 𝛼-
blending – and enable a fast and accurate backward pass by tracking
the traversal of as many sorted splats as required.
To summarize, we provide the following contributions:
• The introduction of anisotropic 3D Gaussians as a high-quality,
unstructured representation of radiance fields.
• An optimization method of 3D Gaussian properties, inter-
leaved with adaptive density control that creates high-quality
representations for captured scenes.
• A fast, differentiable rendering approach for the GPU, which
is visibility-aware, allows anisotropic splatting and fast back-
propagation to achieve high-quality novel view synthesis.
Our results on previously published datasets show that we can opti-
mize our 3D Gaussians from multi-view captures and achieve equal
or better quality than the best quality previous implicit radiance
field approaches. We also can achieve training speeds and quality
similar to the fastest methods and importantly provide the first
real-time rendering with high quality for novel-view synthesis.
2
RELATED WORK
We first briefly overview traditional reconstruction, then discuss
point-based rendering and radiance field work, discussing their
similarity; radiance fields are a vast area, so we focus only on directly
related work. For complete coverage of the field, please see the
excellent recent surveys [Tewari et al. 2022; Xie et al. 2022].
2.1
Traditional Scene Reconstruction and Rendering
The first novel-view synthesis approaches were based on light fields,
first densely sampled [Gortler et al. 1996; Levoy and Hanrahan 1996]
then allowing unstructured capture [Buehler et al. 2001]. The advent
of Structure-from-Motion (SfM) [Snavely et al. 2006] enabled an
entire new domain where a collection of photos could be used to
synthesize novel views. SfM estimates a sparse point cloud during
camera calibration, that was initially used for simple visualization
of 3D space. Subsequent multi-view stereo (MVS) produced im-
pressive full 3D reconstruction algorithms over the years [Goesele
et al. 2007], enabling the development of several view synthesis
algorithms [Chaurasia et al. 2013; Eisemann et al. 2008; Hedman
et al. 2018; Kopanas et al. 2021]. All these methods re-project and
blend the input images into the novel view camera, and use the
geometry to guide this re-projection. These methods produced ex-
cellent results in many cases, but typically cannot completely re-
cover from unreconstructed regions, or from “over-reconstruction”,
when MVS generates inexistent geometry. Recent neural render-
ing algorithms [Tewari et al. 2022] vastly reduce such artifacts and
avoid the overwhelming cost of storing all input images on the GPU,
outperforming these methods on most fronts.
2.2
Neural Rendering and Radiance Fields
Deep learning techniques were adopted early for novel-view synthe-
sis [Flynn et al. 2016; Zhou et al. 2016]; CNNs were used to estimate
blending weights [Hedman et al. 2018], or for texture-space solutions
[Riegler and Koltun 2020; Thies et al. 2019]. The use of MVS-based
geometry is a major drawback of most of these methods; in addition,
the use of CNNs for final rendering frequently results in temporal
flickering.
Volumetric representations for novel-view synthesis were ini-
tiated by Soft3D [Penner and Zhang 2017]; deep-learning tech-
niques coupled with volumetric ray-marching were subsequently
proposed [Henzler et al. 2019; Sitzmann et al. 2019] building on a con-
tinuous differentiable density field to represent geometry. Rendering
using volumetric ray-marching has a significant cost due to the large
number of samples required to query the volume. Neural Radiance
Fields (NeRFs) [Mildenhall et al. 2020] introduced importance sam-
pling and positional encoding to improve quality, but used a large
Multi-Layer Perceptron negatively affecting speed. The success of
NeRF has resulted in an explosion of follow-up methods that address
quality and speed, often by introducing regularization strategies; the
current state-of-the-art in image quality for novel-view synthesis is
Mip-NeRF360 [Barron et al. 2022]. While the rendering quality is
outstanding, training and rendering times remain extremely high;
we are able to equal or in some cases surpass this quality while
providing fast training and real-time rendering.
The most recent methods have focused on faster training and/or
rendering mostly by exploiting three design choices: the use of spa-
tial data structures to store (neural) features that are subsequently
interpolated during volumetric ray-marching, different encodings,
ACM Trans. Graph., Vol. 42, No. 4, Article . Publication date: August 2023.


3D Gaussian Splatting for Real-Time Radiance Field Rendering
•
3
and MLP capacity. Such methods include different variants of space
discretization [Chen et al. 2022b,a; Fridovich-Keil and Yu et al. 2022;
Garbin et al. 2021; Hedman et al. 2021; Reiser et al. 2021; Takikawa
et al. 2021; Wu et al. 2022; Yu et al. 2021], codebooks [Takikawa
et al. 2022], and encodings such as hash tables [Müller et al. 2022],
allowing the use of a smaller MLP or foregoing neural networks
completely [Fridovich-Keil and Yu et al. 2022; Sun et al. 2022].
Most notable of these methods are InstantNGP [Müller et al. 2022]
which uses a hash grid and an occupancy grid to accelerate compu-
tation and a smaller MLP to represent density and appearance; and
Plenoxels [Fridovich-Keil and Yu et al. 2022] that use a sparse voxel
grid to interpolate a continuous density field, and are able to forgo
neural networks altogether. Both rely on Spherical Harmonics: the
former to represent directional effects directly, the latter to encode
its inputs to the color network. While both provide outstanding
results, these methods can still struggle to represent empty space
effectively, depending in part on the scene/capture type. In addition,
image quality is limited in large part by the choice of the structured
grids used for acceleration, and rendering speed is hindered by the
need to query many samples for a given ray-marching step. The un-
structured, explicit GPU-friendly 3D Gaussians we use achieve faster
rendering speed and better quality without neural components.
2.3
Point-Based Rendering and Radiance Fields
Point-based methods efficiently render disconnected and unstruc-
tured geometry samples (i.e., point clouds) [Gross and Pfister 2011].
In its simplest form, point sample rendering [Grossman and Dally
1998] rasterizes an unstructured set of points with a fixed size, for
which it may exploit natively supported point types of graphics APIs
[Sainz and Pajarola 2004] or parallel software rasterization on the
GPU [Laine and Karras 2011; Schütz et al. 2022]. While true to the
underlying data, point sample rendering suffers from holes, causes
aliasing, and is strictly discontinuous. Seminal work on high-quality
point-based rendering addresses these issues by “splatting” point
primitives with an extent larger than a pixel, e.g., circular or elliptic
discs, ellipsoids, or surfels [Botsch et al. 2005; Pfister et al. 2000; Ren
et al. 2002; Zwicker et al. 2001b].
There has been recent interest in differentiable point-based render-
ing techniques [Wiles et al. 2020; Yifan et al. 2019]. Points have been
augmented with neural features and rendered using a CNN [Aliev
et al. 2020; Rückert et al. 2022] resulting in fast or even real-time
view synthesis; however they still depend on MVS for the initial
geometry, and as such inherit its artifacts, most notably over- or
under-reconstruction in hard cases such as featureless/shiny areas
or thin structures.
Point-based 𝛼-blending and NeRF-style volumetric rendering
share essentially the same image formation model. Specifically, the
color 𝐶is given by volumetric rendering along a ray:
𝐶=
𝑁
∑︁
𝑖=1
𝑇𝑖(1 −exp(−𝜎𝑖𝛿𝑖))c𝑖
with 𝑇𝑖= exp ©
­
«
−
𝑖−1
∑︁
𝑗=1
𝜎𝑗𝛿𝑗ª
®
¬
,
(1)
where samples of density 𝜎, transmittance 𝑇, and color c are taken
along the ray with intervals 𝛿𝑖. This can be re-written as
𝐶=
𝑁
∑︁
𝑖=1
𝑇𝑖𝛼𝑖c𝑖,
(2)
with
𝛼𝑖= (1 −exp(−𝜎𝑖𝛿𝑖)) and 𝑇𝑖=
𝑖−1
Ö
𝑗=1
(1 −𝛼𝑖).
A typical neural point-based approach (e.g., [Kopanas et al. 2022,
2021]) computes the color 𝐶of a pixel by blending N ordered points
overlapping the pixel:
𝐶=
∑︁
𝑖∈N
𝑐𝑖𝛼𝑖
𝑖−1
Ö
𝑗=1
(1 −𝛼𝑗),
(3)
where c𝑖is the color of each point and 𝛼𝑖is given by evaluating a
2D Gaussian with covariance Σ [Yifan et al. 2019] multiplied with a
learned per-point opacity.
From Eq. 2 and Eq. 3, we can clearly see that the image formation
model is the same. However, the rendering algorithm is very differ-
ent. NeRFs are a continuous representation implicitly representing
empty/occupied space; expensive random sampling is required to
find the samples in Eq. 2 with consequent noise and computational
expense. In contrast, points are an unstructured, discrete represen-
tation that is flexible enough to allow creation, destruction, and
displacement of geometry similar to NeRF. This is achieved by opti-
mizing opacity and positions, as shown by previous work [Kopanas
et al. 2021], while avoiding the shortcomings of a full volumetric
representation.
Pulsar [Lassner and Zollhofer 2021] achieves fast sphere rasteri-
zation which inspired our tile-based and sorting renderer. However,
given the analysis above, we want to maintain (approximate) con-
ventional 𝛼-blending on sorted splats to have the advantages of vol-
umetric representations: Our rasterization respects visibility order
in contrast to their order-independent method. In addition, we back-
propagate gradients on all splats in a pixel and rasterize anisotropic
splats. These elements all contribute to the high visual quality of
our results (see Sec. 7.3). In addition, previous methods mentioned
above also use CNNs for rendering, which results in temporal in-
stability. Nonetheless, the rendering speed of Pulsar [Lassner and
Zollhofer 2021] and ADOP [Rückert et al. 2022] served as motivation
to develop our fast rendering solution.
While focusing on specular effects, the diffuse point-based ren-
dering track of Neural Point Catacaustics [Kopanas et al. 2022]
overcomes this temporal instability by using an MLP, but still re-
quired MVS geometry as input. The most recent method [Zhang
et al. 2022] in this category does not require MVS, and also uses
SH for directions; however, it can only handle scenes of one object
and needs masks for initialization. While fast for small resolutions
and low point counts, it is unclear how it can scale to scenes of
typical datasets [Barron et al. 2022; Hedman et al. 2018; Knapitsch
et al. 2017]. We use 3D Gaussians for a more flexible scene rep-
resentation, avoiding the need for MVS geometry and achieving
real-time rendering thanks to our tile-based rendering algorithm
for the projected Gaussians.
ACM Trans. Graph., Vol. 42, No. 4, Article . Publication date: August 2023.


4
•
Bernhard Kerbl, Georgios Kopanas, Thomas Leimkühler, and George Drettakis
A recent approach [Xu et al. 2022] uses points to represent a
radiance field with a radial basis function approach. They employ
point pruning and densification techniques during optimization, but
use volumetric ray-marching and cannot achieve real-time display
rates.
In the domain of human performance capture, 3D Gaussians have
been used to represent captured human bodies [Rhodin et al. 2015;
Stoll et al. 2011]; more recently they have been used with volumetric
ray-marching for vision tasks [Wang et al. 2023]. Neural volumetric
primitives have been proposed in a similar context [Lombardi et al.
2021]. While these methods inspired the choice of 3D Gaussians as
our scene representation, they focus on the specific case of recon-
structing and rendering a single isolated object (a human body or
face), resulting in scenes with small depth complexity. In contrast,
our optimization of anisotropic covariance, our interleaved optimiza-
tion/density control, and efficient depth sorting for rendering allow
us to handle complete, complex scenes including background, both
indoors and outdoors and with large depth complexity.
3
OVERVIEW
The input to our method is a set of images of a static scene, together
with the corresponding cameras calibrated by SfM [Schönberger
and Frahm 2016] which produces a sparse point cloud as a side-
effect. From these points we create a set of 3D Gaussians (Sec. 4),
defined by a position (mean), covariance matrix and opacity 𝛼, that
allows a very flexible optimization regime. This results in a reason-
ably compact representation of the 3D scene, in part because highly
anisotropic volumetric splats can be used to represent fine structures
compactly. The directional appearance component (color) of the
radiance field is represented via spherical harmonics (SH), following
standard practice [Fridovich-Keil and Yu et al. 2022; Müller et al.
2022]. Our algorithm proceeds to create the radiance field represen-
tation (Sec. 5) via a sequence of optimization steps of 3D Gaussian
parameters, i.e., position, covariance, 𝛼and SH coefficients inter-
leaved with operations for adaptive control of the Gaussian density.
The key to the efficiency of our method is our tile-based rasterizer
(Sec. 6) that allows 𝛼-blending of anisotropic splats, respecting visi-
bility order thanks to fast sorting. Out fast rasterizer also includes
a fast backward pass by tracking accumulated 𝛼values, without a
limit on the number of Gaussians that can receive gradients. The
overview of our method is illustrated in Fig. 2.
4
DIFFERENTIABLE 3D GAUSSIAN SPLATTING
Our goal is to optimize a scene representation that allows high-
quality novel view synthesis, starting from a sparse set of (SfM)
points without normals. To do this, we need a primitive that inherits
the properties of differentiable volumetric representations, while
at the same time being unstructured and explicit to allow very fast
rendering. We choose 3D Gaussians, which are differentiable and
can be easily projected to 2D splats allowing fast 𝛼-blending for
rendering.
Our representation has similarities to previous methods that use
2D points [Kopanas et al. 2021; Yifan et al. 2019] and assume each
point is a small planar circle with a normal. Given the extreme
sparsity of SfM points it is very hard to estimate normals. Similarly,
optimizing very noisy normals from such an estimation would be
very challenging. Instead, we model the geometry as a set of 3D
Gaussians that do not require normals. Our Gaussians are defined
by a full 3D covariance matrix Σ defined in world space [Zwicker
et al. 2001a] centered at point (mean) 𝜇:
𝐺(𝑥) = 𝑒−1
2 (𝑥)𝑇Σ−1(𝑥)
(4)
. This Gaussian is multiplied by 𝛼in our blending process.
However, we need to project our 3D Gaussians to 2D for rendering.
Zwicker et al. [2001a] demonstrate how to do this projection to
image space. Given a viewing transformation 𝑊the covariance
matrix Σ′ in camera coordinates is given as follows:
Σ′ = 𝐽𝑊Σ 𝑊𝑇𝐽𝑇
(5)
where 𝐽is the Jacobian of the affine approximation of the projective
transformation. Zwicker et al. [2001a] also show that if we skip the
third row and column of Σ′, we obtain a 2×2 variance matrix with
the same structure and properties as if we would start from planar
points with normals, as in previous work [Kopanas et al. 2021].
An obvious approach would be to directly optimize the covariance
matrix Σ to obtain 3D Gaussians that represent the radiance field.
However, covariance matrices have physical meaning only when
they are positive semi-definite. For our optimization of all our pa-
rameters, we use gradient descent that cannot be easily constrained
to produce such valid matrices, and update steps and gradients can
very easily create invalid covariance matrices.
As a result, we opted for a more intuitive, yet equivalently ex-
pressive representation for optimization. The covariance matrix Σ
of a 3D Gaussian is analogous to describing the configuration of an
ellipsoid. Given a scaling matrix 𝑆and rotation matrix 𝑅, we can
find the corresponding Σ:
Σ = 𝑅𝑆𝑆𝑇𝑅𝑇
(6)
To allow independent optimization of both factors, we store them
separately: a 3D vector 𝑠for scaling and a quaternion 𝑞to represent
rotation. These can be trivially converted to their respective matrices
and combined, making sure to normalize 𝑞to obtain a valid unit
quaternion.
To avoid significant overhead due to automatic differentiation
during training, we derive the gradients for all parameters explicitly.
Details of the exact derivative computations are in appendix A.
This representation of anisotropic covariance – suitable for op-
timization – allows us to optimize 3D Gaussians to adapt to the
geometry of different shapes in captured scenes, resulting in a fairly
compact representation. Fig. 3 illustrates such cases.
5
OPTIMIZATION WITH ADAPTIVE DENSITY
CONTROL OF 3D GAUSSIANS
The core of our approach is the optimization step, which creates
a dense set of 3D Gaussians accurately representing the scene for
free-view synthesis. In addition to positions 𝑝, 𝛼, and covariance
Σ, we also optimize SH coefficients representing color 𝑐of each
Gaussian to correctly capture the view-dependent appearance of
the scene. The optimization of these parameters is interleaved with
steps that control the density of the Gaussians to better represent
the scene.
ACM Trans. Graph., Vol. 42, No. 4, Article . Publication date: August 2023.


3D Gaussian Splatting for Real-Time Radiance Field Rendering
•
5
Diﬀerentiable
Tile Rasterizer
Adaptive
Density Control
Projection
Initialization
SfM Points
3D Gaussians
Image
Camera
Gradient Flow
Operation Flow
Fig. 2. Optimization starts with the sparse SfM point cloud and creates a set of 3D Gaussians. We then optimize and adaptively control the density of this set
of Gaussians. During optimization we use our fast tile-based renderer, allowing competitive training times compared to SOTA fast radiance field methods.
Once trained, our renderer allows real-time navigation for a wide variety of scenes.
Original
Shrunken
Gaussians
Fig. 3. We visualize the 3D Gaussians after optimization by shrinking them
60% (far right). This clearly shows the anisotropic shapes of the 3D Gaussians
that compactly represent complex geometry after optimization. Left the
actual rendered image.
5.1
Optimization
The optimization is based on successive iterations of rendering and
comparing the resulting image to the training views in the captured
dataset. Inevitably, geometry may be incorrectly placed due to the
ambiguities of 3D to 2D projection. Our optimization thus needs to
be able to create geometry and also destroy or move geometry if it
has been incorrectly positioned. The quality of the parameters of the
covariances of the 3D Gaussians is critical for the compactness of
the representation since large homogeneous areas can be captured
with a small number of large anisotropic Gaussians.
We use Stochastic Gradient Descent techniques for optimization,
taking full advantage of standard GPU-accelerated frameworks,
and the ability to add custom CUDA kernels for some operations,
following recent best practice [Fridovich-Keil and Yu et al. 2022;
Sun et al. 2022]. In particular, our fast rasterization (see Sec. 6) is
critical in the efficiency of our optimization, since it is the main
computational bottleneck of the optimization.
We use a sigmoid activation function for 𝛼to constrain it in
the [0 −1) range and obtain smooth gradients, and an exponential
activation function for the scale of the covariance for similar reasons.
We estimate the initial covariance matrix as an isotropic Gaussian
with axes equal to the mean of the distance to the closest three points.
We use a standard exponential decay scheduling technique similar
to Plenoxels [Fridovich-Keil and Yu et al. 2022], but for positions
only. The loss function is L1 combined with a D-SSIM term:
L = (1 −𝜆)L1 + 𝜆LD-SSIM
(7)
We use 𝜆= 0.2 in all our tests. We provide details of the learning
schedule and other elements in Sec. 7.1.
5.2
Adaptive Control of Gaussians
We start with the initial set of sparse points from SfM and then apply
our method to adaptively control the number of Gaussians and their
density over unit volume1, allowing us to go from an initial sparse
set of Gaussians to a denser set that better represents the scene, and
with correct parameters. After optimization warm-up (see Sec. 7.1),
we densify every 100 iterations and remove any Gaussians that are
essentially transparent, i.e., with 𝛼less than a threshold 𝜖𝛼.
Our adaptive control of the Gaussians needs to populate empty
areas. It focuses on regions with missing geometric features (“under-
reconstruction”), but also in regions where Gaussians cover large
areas in the scene (which often correspond to “over-reconstruction”).
We observe that both have large view-space positional gradients.
Intuitively, this is likely because they correspond to regions that are
not yet well reconstructed, and the optimization tries to move the
Gaussians to correct this.
Since both cases are good candidates for densification, we den-
sify Gaussians with an average magnitude of view-space position
gradients above a threshold 𝜏pos, which we set to 0.0002 in our tests.
We next present details of this process, illustrated in Fig. 4.
For small Gaussians that are in under-reconstructed regions, we
need to cover the new geometry that must be created. For this, it is
preferable to clone the Gaussians, by simply creating a copy of the
same size, and moving it in the direction of the positional gradient.
On the other hand, large Gaussians in regions with high variance
need to be split into smaller Gaussians. We replace such Gaussians
by two new ones, and divide their scale by a factor of 𝜙= 1.6 which
we determined experimentally. We also initialize their position by
using the original 3D Gaussian as a PDF for sampling.
In the first case we detect and treat the need for increasing both
the total volume of the system and the number of Gaussians, while
in the second case we conserve total volume but increase the num-
ber of Gaussians. Similar to other volumetric representations, our
optimization can get stuck with floaters close to the input cameras;
in our case this may result in an unjustified increase in the Gaussian
density. An effective way to moderate the increase in the number
of Gaussians is to set the 𝛼value close to zero every 𝑁= 3000
1Density of Gaussians should not be confused of course with density 𝜎in the NeRF
literature.
ACM Trans. Graph., Vol. 42, No. 4, Article . Publication date: August 2023.


6
•
Bernhard Kerbl, Georgios Kopanas, Thomas Leimkühler, and George Drettakis
Under-
Reconstruction
Clone
Split
Optimization
Continues
…
…
Optimization
Continues
Over-
Reconstruction
Fig. 4.
Our adaptive Gaussian densification scheme. Top row (under-
reconstruction): When small-scale geometry (black outline) is insufficiently
covered, we clone the respective Gaussian. Bottom row (over-reconstruction):
If small-scale geometry is represented by one large splat, we split it in two.
iterations. The optimization then increases the 𝛼for the Gaussians
where this is needed while allowing our culling approach to remove
Gaussians with 𝛼less than 𝜖𝛼as described above. Gaussians may
shrink or grow and considerably overlap with others, but we peri-
odically remove Gaussians that are very large in worldspace and
those that have a big footprint in viewspace. This strategy results
in overall good control over the total number of Gaussians. The
Gaussians in our model remain primitives in Euclidean space at all
times; unlike other methods [Barron et al. 2022; Fridovich-Keil and
Yu et al. 2022], we do not require space compaction, warping or
projection strategies for distant or large Gaussians.
6
FAST DIFFERENTIABLE RASTERIZER FOR GAUSSIANS
Our goals are to have fast overall rendering and fast sorting to allow
approximate 𝛼-blending – including for anisotropic splats – and to
avoid hard limits on the number of splats that can receive gradients
that exist in previous work [Lassner and Zollhofer 2021].
To achieve these goals, we design a tile-based rasterizer for Gauss-
ian splats inspired by recent software rasterization approaches [Lass-
ner and Zollhofer 2021] to pre-sort primitives for an entire image
at a time, avoiding the expense of sorting per pixel that hindered
previous 𝛼-blending solutions [Kopanas et al. 2022, 2021]. Our fast
rasterizer allows efficient backpropagation over an arbitrary num-
ber of blended Gaussians with low additional memory consump-
tion, requiring only a constant overhead per pixel. Our rasterization
pipeline is fully differentiable, and given the projection to 2D (Sec. 4)
can rasterize anisotropic splats similar to previous 2D splatting
methods [Kopanas et al. 2021].
Our method starts by splitting the screen into 16×16 tiles, and
then proceeds to cull 3D Gaussians against the view frustum and
each tile. Specifically, we only keep Gaussians with a 99% confi-
dence interval intersecting the view frustum. Additionally, we use a
guard band to trivially reject Gaussians at extreme positions (i.e.,
those with means close to the near plane and far outside the view
frustum), since computing their projected 2D covariance would
be unstable. We then instantiate each Gaussian according to the
number of tiles they overlap and assign each instance a key that
combines view space depth and tile ID. We then sort Gaussians
based on these keys using a single fast GPU Radix sort [Merrill
and Grimshaw 2010]. Note that there is no additional per-pixel or-
dering of points, and blending is performed based on this initial
sorting. As a consequence, our 𝛼-blending can be approximate in
some configurations. However, these approximations become negli-
gible as splats approach the size of individual pixels. We found that
this choice greatly enhances training and rendering performance
without producing visible artifacts in converged scenes.
After sorting Gaussians, we produce a list for each tile by iden-
tifying the first and last depth-sorted entry that splats to a given
tile. For rasterization, we launch one thread block for each tile. Each
block first collaboratively loads packets of Gaussians into shared
memory and then, for a given pixel, accumulates color and 𝛼values
by traversing the lists front-to-back, thus maximizing the gain in
parallelism both for data loading/sharing and processing. When we
reach a target saturation of 𝛼in a pixel, the corresponding thread
stops. At regular intervals, threads in a tile are queried and the pro-
cessing of the entire tile terminates when all pixels have saturated
(i.e., 𝛼goes to 1). Details of sorting and a high-level overview of the
overall rasterization approach are given in Appendix C.
During rasterization, the saturation of 𝛼is the only stopping cri-
terion. In contrast to previous work, we do not limit the number
of blended primitives that receive gradient updates. We enforce
this property to allow our approach to handle scenes with an arbi-
trary, varying depth complexity and accurately learn them, without
having to resort to scene-specific hyperparameter tuning. During
the backward pass, we must therefore recover the full sequence of
blended points per-pixel in the forward pass. One solution would
be to store arbitrarily long lists of blended points per-pixel in global
memory [Kopanas et al. 2021]. To avoid the implied dynamic mem-
ory management overhead, we instead choose to traverse the per-
tile lists again; we can reuse the sorted array of Gaussians and tile
ranges from the forward pass. To facilitate gradient computation,
we now traverse them back-to-front.
The traversal starts from the last point that affected any pixel in
the tile, and loading of points into shared memory again happens
collaboratively. Additionally, each pixel will only start (expensive)
overlap testing and processing of points if their depth is lower than
or equal to the depth of the last point that contributed to its color
during the forward pass. Computation of the gradients described in
Sec. 4 requires the accumulated opacity values at each step during
the original blending process. Rather than trasversing an explicit
list of progressively shrinking opacities in the backward pass, we
can recover these intermediate opacities by storing only the total
accumulated opacity at the end of the forward pass. Specifically, each
point stores the final accumulated opacity 𝛼in the forward process;
we divide this by each point’s 𝛼in our back-to-front traversal to
obtain the required coefficients for gradient computation.
7
IMPLEMENTATION, RESULTS AND EVALUATION
We next discuss some details of implementation, present results and
the evaluation of our algorithm compared to previous work and
ablation studies.
ACM Trans. Graph., Vol. 42, No. 4, Article . Publication date: August 2023.


3D Gaussian Splatting for Real-Time Radiance Field Rendering
•
7
Ground Truth
Ours
Mip-NeRF360
InstantNGP
Plenoxels
Fig. 5. We show comparisons of ours to previous methods and the corresponding ground truth images from held-out test views. The scenes are, from the top
down: Bicycle, Garden, Stump, Counter and Room from the Mip-NeRF360 dataset; Playroom, DrJohnson from the Deep Blending dataset [Hedman et al.
2018] and Truck and Train from Tanks&Temples. Non-obvious differences in quality highlighted by arrows/insets.
ACM Trans. Graph., Vol. 42, No. 4, Article . Publication date: August 2023.


8
•
Bernhard Kerbl, Georgios Kopanas, Thomas Leimkühler, and George Drettakis
Table 1. Quantitative evaluation of our method compared to previous work, computed over three datasets. Results marked with dagger † have been directly
adopted from the original paper, all others were obtained in our own experiments.
Dataset
Mip-NeRF360
Tanks&Temples
Deep Blending
Method|Metric
𝑆𝑆𝐼𝑀↑
𝑃𝑆𝑁𝑅↑
𝐿𝑃𝐼𝑃𝑆↓
Train
FPS
Mem
𝑆𝑆𝐼𝑀↑
𝑃𝑆𝑁𝑅↑
𝐿𝑃𝐼𝑃𝑆↓
Train
FPS
Mem
𝑆𝑆𝐼𝑀↑
𝑃𝑆𝑁𝑅↑
𝐿𝑃𝐼𝑃𝑆↓
Train
FPS
Mem
Plenoxels
0.626
23.08
0.463
25m49s
6.79
2.1GB
0.719
21.08
0.379
25m5s
13.0
2.3GB
0.795
23.06
0.510
27m49s
11.2
2.7GB
INGP-Base
0.671
25.30
0.371
5m37s
11.7
13MB
0.723
21.72
0.330
5m26s
17.1
13MB
0.797
23.62
0.423
6m31s
3.26
13MB
INGP-Big
0.699
25.59
0.331
7m30s
9.43
48MB
0.745
21.92
0.305
6m59s
14.4
48MB
0.817
24.96
0.390
8m
2.79
48MB
M-NeRF360
0.792†
27.69†
0.237†
48h
0.06
8.6MB
0.759
22.22
0.257
48h
0.14
8.6MB
0.901
29.40
0.245
48h
0.09
8.6MB
Ours-7K
0.770
25.60
0.279
6m25s
160
523MB
0.767
21.20
0.280
6m55s
197
270MB
0.875
27.78
0.317
4m35s
172
386MB
Ours-30K
0.815
27.21
0.214
41m33s
134
734MB
0.841
23.14
0.183
26m54s
154
411MB
0.903
29.41
0.243
36m2s
137
676MB
7K iterations
7K iterations
30K iterations
30K iterations
Fig. 6. For some scenes (above) we can see that even at 7K iterations (∼5min
for this scene), our method has captured the train quite well. At 30K itera-
tions (∼35min) the background artifacts have been reduced significantly. For
other scenes (below), the difference is barely visible; 7K iterations (∼8min)
is already very high quality.
Table 2. PSNR scores for Synthetic NeRF, we start with 100K randomly
initialized points. Competing metrics extracted from respective papers.
Mic
Chair
Ship
Materials
Lego
Drums
Ficus
Hotdog
Avg.
Plenoxels
33.26
33.98
29.62
29.14
34.10
25.35
31.83
36.81
31.76
INGP-Base
36.22
35.00
31.10
29.78
36.39
26.02
33.51
37.40
33.18
Mip-NeRF
36.51
35.14
30.41
30.71
35.70
25.48
33.29
37.48
33.09
Point-NeRF
35.95
35.40
30.97
29.61
35.04
26.06
36.13
37.30
33.30
Ours-30K
35.36
35.83
30.80
30.00
35.78
26.15
34.87
37.72
33.32
7.1
Implementation
We implemented our method in Python using the PyTorch frame-
work and wrote custom CUDA kernels for rasterization that are
extended versions of previous methods [Kopanas et al. 2021], and
use the NVIDIA CUB sorting routines for the fast Radix sort [Mer-
rill and Grimshaw 2010]. We also built an interactive viewer using
the open-source SIBR [Bonopera et al. 2020], used for interactive
viewing. We used this implementation to measure our achieved
frame rates. The source code and all our data are available at:
https://repo-sam.inria.fr/fungraph/3d-gaussian-splatting/
Optimization Details. For stability, we “warm-up” the computa-
tion in lower resolution. Specifically, we start the optimization using
4 times smaller image resolution and we upsample twice after 250
and 500 iterations.
SH coefficient optimization is sensitive to the lack of angular
information. For typical “NeRF-like” captures where a central object
is observed by photos taken in the entire hemisphere around it, the
optimization works well. However, if the capture has angular regions
missing (e.g., when capturing the corner of a scene, or performing
an “inside-out” [Hedman et al. 2016] capture) completely incorrect
values for the zero-order component of the SH (i.e., the base or
diffuse color) can be produced by the optimization. To overcome
this problem we start by optimizing only the zero-order component,
and then introduce one band of the SH after every 1000 iterations
until all 4 bands of SH are represented.
7.2
Results and Evaluation
Results. We tested our algorithm on a total of 13 real scenes
taken from previously published datasets and the synthetic Blender
dataset [Mildenhall et al. 2020]. In particular, we tested our ap-
proach on the full set of scenes presented in Mip-Nerf360 [Barron
et al. 2022], which is the current state of the art in NeRF rendering
quality, two scenes from the Tanks&Temples dataset [2017] and
two scenes provided by Hedman et al. [Hedman et al. 2018]. The
scenes we chose have very different capture styles, and cover both
bounded indoor scenes and large unbounded outdoor environments.
We use the same hyperparameter configuration for all experiments
in our evaluation. All results are reported running on an A6000 GPU,
except for the Mip-NeRF360 method (see below).
In supplemental, we show a rendered video path for a selection
of scenes that contain views far from the input photos.
Real-World Scenes. In terms of quality, the current state-of-the-
art is Mip-Nerf360 [Barron et al. 2021]. We compare against this
method as a quality benchmark. We also compare against two of
the most recent fast NeRF methods: InstantNGP [Müller et al. 2022]
and Plenoxels [Fridovich-Keil and Yu et al. 2022].
We use a train/test split for datasets, using the methodology
suggested by Mip-NeRF360, taking every 8th photo for test, for con-
sistent and meaningful comparisons to generate the error metrics,
using the standard PSNR, L-PIPS, and SSIM metrics used most fre-
quently in the literature; please see Table 1. All numbers in the table
are from our own runs of the author’s code for all previous meth-
ods, except for those of Mip-NeRF360 on their dataset, in which we
copied the numbers from the original publication to avoid confusion
about the current SOTA. For the images in our figures, we used our
own run of Mip-NeRF360: the numbers for these runs are in Appen-
dix D. We also show the average training time, rendering speed, and
memory used to store optimized parameters. We report results for a
basic configuration of InstantNGP (Base) that run for 35K iterations
as well as a slightly larger network suggested by the authors (Big),
and two configurations, 7K and 30K iterations for ours. We show
ACM Trans. Graph., Vol. 42, No. 4, Article . Publication date: August 2023.


3D Gaussian Splatting for Real-Time Radiance Field Rendering
•
9
Table 3. PSNR Score for ablation runs. For this experiment, we manually downsampled high-resolution versions of each scene’s input images to the established
rendering resolution of our other experiments. Doing so reduces random artifacts (e.g., due to JPEG compression in the pre-downscaled Mip-NeRF360 inputs).
Truck-5K
Garden-5K
Bicycle-5K
Truck-30K
Garden-30K
Bicycle-30K
Average-5K
Average-30K
Limited-BW
14.66
22.07
20.77
13.84
22.88
20.87
19.16
19.19
Random Init
16.75
20.90
19.86
18.02
22.19
21.05
19.17
20.42
No-Split
18.31
23.98
22.21
20.59
26.11
25.02
21.50
23.90
No-SH
22.36
25.22
22.88
24.39
26.59
25.08
23.48
25.35
No-Clone
22.29
25.61
22.15
24.82
27.47
25.46
23.35
25.91
Isotropic
22.40
25.49
22.81
23.89
27.00
24.81
23.56
25.23
Full
22.71
25.82
23.18
24.81
27.70
25.65
23.90
26.05
the difference in visual quality for our two configurations in Fig. 6.
In many cases, quality at 7K iterations is already quite good.
The training times vary over datasets and we report them sepa-
rately. Note that image resolutions also vary over datasets. In the
project website, we provide all the renders of test views we used to
compute the statistics for all the methods (ours and previous work)
on all scenes. Note that we kept the native input resolution for all
renders.
The table shows that our fully converged model achieves qual-
ity that is on par and sometimes slightly better than the SOTA
Mip-NeRF360 method; note that on the same hardware, their aver-
age training time was 48 hours2, compared to our 35-45min, and
their rendering time is 10s/frame. We achieve comparable quality
to InstantNGP and Plenoxels after 5-10m of training, but additional
training time allows us to achieve SOTA quality which is not the
case for the other fast methods. For Tanks & Temples, we achieve
similar quality as the basic InstantNGP at a similar training time
(∼7min in our case).
We also show visual results of this comparison for a left-out
test view for ours and the previous rendering methods selected
for comparison in Fig. 5; the results of our method are for 30K
iterations of training. We see that in some cases even Mip-NeRF360
has remaining artifacts that our method avoids (e.g., blurriness in
vegetation – in Bicycle, Stump – or on the walls in Room). In the
supplemental video and web page we provide comparisons of paths
from a distance. Our method tends to preserve visual detail of well-
covered regions even from far away, which is not always the case
for previous methods.
Synthetic Bounded Scenes. In addition to realistic scenes, we also
evaluate our approach on the synthetic Blender dataset [Mildenhall
et al. 2020]. The scenes in question provide an exhaustive set of
views, are limited in size, and provide exact camera parameters. In
such scenarios, we can achieve state-of-the-art results even with
random initialization: we start training from 100K uniformly random
Gaussians inside a volume that encloses the scene bounds. Our
approach quickly and automatically prunes them to about 6–10K
meaningful Gaussians. The final size of the trained model after 30K
iterations reaches about 200–500K Gaussians per scene. We report
and compare our achieved PSNR scores with previous methods in
Table 2 using a white background for compatibility. Examples can
2We trained Mip-NeRF360 on a 4-GPU A100 node for 12 hours, equivalent to 48 hours
on a single GPU. Note that A100’s are faster than A6000 GPUs.
be seen in Fig. 10 (second image from the left) and in supplemental
material. The trained synthetic scenes rendered at 180–300 FPS.
Compactness. In comparison to previous explicit scene representa-
tions, the anisotropic Gaussians used in our optimization are capable
of modelling complex shapes with a lower number of parameters.
We showcase this by evaluating our approach against the highly
compact, point-based models obtained by [Zhang et al. 2022]. We
start from their initial point cloud which is obtained by space carving
with foreground masks and optimize until we break even with their
reported PSNR scores. This usually happens within 2–4 minutes.
We surpass their reported metrics using approximately one-fourth
of their point count, resulting in an average model size of 3.8 MB,
as opposed to their 9 MB. We note that for this experiment, we only
used two degrees of our spherical harmonics, similar to theirs.
7.3
Ablations
We isolated the different contributions and algorithmic choices
we made and constructed a set of experiments to measure their
effect. Specifically we test the following aspects of our algorithm:
initialization from SfM, our densification strategies, anisotropic
covariance, the fact that we allow an unlimited number of splats
to have gradients and use of spherical harmonics. The quantitative
effect of each choice is summarized in Table 3.
Initialization from SfM. We also assess the importance of initializ-
ing the 3D Gaussians from the SfM point cloud. For this ablation, we
uniformly sample a cube with a size equal to three times the extent
of the input camera’s bounding box. We observe that our method
performs relatively well, avoiding complete failure even without the
SfM points. Instead, it degrades mainly in the background, see Fig. 7.
Also in areas not well covered from training views, the random
initialization method appears to have more floaters that cannot be
removed by optimization. On the other hand, the synthetic NeRF
dataset does not have this behavior because it has no background
and is well constrained by the input cameras (see discussion above).
Densification. We next evaluate our two densification methods,
more specifically the clone and split strategy described in Sec. 5.
We disable each method separately and optimize using the rest of
the method unchanged. Results show that splitting big Gaussians
is important to allow good reconstruction of the background as
seen in Fig. 8, while cloning the small Gaussians instead of splitting
them allows for a better and faster convergence especially when
thin structures appear in the scene.
ACM Trans. Graph., Vol. 42, No. 4, Article . Publication date: August 2023.


10
•
Bernhard Kerbl, Georgios Kopanas, Thomas Leimkühler, and George Drettakis
SfM
Random
Fig. 7.
Initialization with SfM points helps. Above: initialization with a
random point cloud. Below: initialization using SfM points.
Full-5k 
No Clone-5k
No Split-5k
Fig. 8.
Ablation of densification strategy for the two cases "clone" and
"split" (Sec. 5).
Unlimited depth complexity of splats with gradients. We evaluate
if skipping the gradient computation after the 𝑁front-most points
Fig. 9. If we limit the number of points that receive gradients, the effect on
visual quality is significant. Left: limit of 10 Gaussians that receive gradients.
Right: our full method.
will give us speed without sacrificing quality, as suggested in Pul-
sar [Lassner and Zollhofer 2021]. In this test, we choose N=10, which
is two times higher than the default value in Pulsar, but it led to
unstable optimization because of the severe approximation in the
gradient computation. For the Truck scene, quality degraded by
11dB in PSNR (see Table 3, Limited-BW), and the visual outcome is
shown in Fig. 9 for Garden.
Anisotropic Covariance. An important algorithmic choice in our
method is the optimization of the full covariance matrix for the 3D
Gaussians. To demonstrate the effect of this choice, we perform an
ablation where we remove anisotropy by optimizing a single scalar
value that controls the radius of the 3D Gaussian on all three axes.
The results of this optimization are presented visually in Fig. 10.
We observe that the anisotropy significantly improves the quality
of the 3D Gaussian’s ability to align with surfaces, which in turn
allows for much higher rendering quality while maintaining the
same number of points.
Spherical Harmonics. Finally, the use of spherical harmonics im-
proves our overall PSNR scores since they compensate for the view-
dependent effects (Table 3).
7.4
Limitations
Our method is not without limitations. In regions where the scene
is not well observed we have artifacts; in such regions, other meth-
ods also struggle (e.g., Mip-NeRF360 in Fig. 11). Even though the
anisotropic Gaussians have many advantages as described above,
our method can create elongated artifacts or “splotchy” Gaussians
(see Fig. 12); again previous methods also struggle in these cases.
We also occasionally have popping artifacts when our optimiza-
tion creates large Gaussians; this tends to happen in regions with
view-dependent appearance. One reason for these popping artifacts
is the trivial rejection of Gaussians via a guard band in the rasterizer.
A more principled culling approach would alleviate these artifacts.
Another factor is our simple visibility algorithm, which can lead to
Gaussians suddenly switching depth/blending order. This could be
addressed by antialiasing, which we leave as future work. Also, we
currently do not apply any regularization to our optimization; doing
so would help with both the unseen region and popping artifacts.
While we used the same hyperparameters for our full evaluation,
early experiments show that reducing the position learning rate can
be necessary to converge in very large scenes (e.g., urban datasets).
ACM Trans. Graph., Vol. 42, No. 4, Article . Publication date: August 2023.


3D Gaussian Splatting for Real-Time Radiance Field Rendering
•
11
Ground 
Truth
Full
Isotropic
Ground 
Truth
Full
Isotropic
Ground 
Truth
Full
Isotropic
Fig. 10. We train scenes with Gaussian anisotropy disabled and enabled. The use of anisotropic volumetric splats enables modelling of fine structures and has
a significant impact on visual quality. Note that for illustrative purposes, we restricted Ficus to use no more than 5k Gaussians in both configurations.
Even though we are very compact compared to previous point-
based approaches, our memory consumption is significantly higher
than NeRF-based solutions. During training of large scenes, peak
GPU memory consumption can exceed 20 GB in our unoptimized
prototype. However, this figure could be significantly reduced by a
careful low-level implementation of the optimization logic (similar
to InstantNGP). Rendering the trained scene requires sufficient GPU
memory to store the full model (several hundred megabytes for
large-scale scenes) and an additional 30–500 MB for the rasterizer,
depending on scene size and image resolution. We note that there
are many opportunities to further reduce memory consumption
of our method. Compression techniques for point clouds is a well-
studied field [De Queiroz and Chou 2016]; it would be interesting to
see how such approaches could be adapted to our representation.
Fig. 11. Comparison of failure artifacts: Mip-NeRF360 has “floaters” and
grainy appearance (left, foreground), while our method produces coarse,
anisoptropic Gaussians resulting in low-detail visuals (right, background).
Train scene.
Fig. 12. In views that have little overlap with those seen during training,
our method may produce artifacts (right). Again, Mip-NeRF360 also has
artifacts in these cases (left). DrJohnson scene.
8
DISCUSSION AND CONCLUSIONS
We have presented the first approach that truly allows real-time,
high-quality radiance field rendering, in a wide variety of scenes
and capture styles, while requiring training times competitive with
the fastest previous methods.
Our choice of a 3D Gaussian primitive preserves properties of
volumetric rendering for optimization while directly allowing fast
splat-based rasterization. Our work demonstrates that – contrary to
widely accepted opinion – a continuous representation is not strictly
necessary to allow fast and high-quality radiance field training.
The majority (∼80%) of our training time is spent in Python code,
since we built our solution in PyTorch to allow our method to be
easily used by others. Only the rasterization routine is implemented
as optimized CUDA kernels. We expect that porting the remaining
optimization entirely to CUDA, as e.g., done in InstantNGP [Müller
et al. 2022], could enable significant further speedup for applications
where performance is essential.
We also demonstrated the importance of building on real-time
rendering principles, exploiting the power of the GPU and speed of
software rasterization pipeline architecture. These design choices
are the key to performance both for training and real-time render-
ing, providing a competitive edge in performance over previous
volumetric ray-marching.
It would be interesting to see if our Gaussians can be used to per-
form mesh reconstructions of the captured scene. Aside from prac-
tical implications given the widespread use of meshes, this would
allow us to better understand where our method stands exactly in
the continuum between volumetric and surface representations.
In conclusion, we have presented the first real-time rendering
solution for radiance fields, with rendering quality that matches the
best expensive previous methods, with training times competitive
with the fastest existing solutions.
ACKNOWLEDGMENTS
This research was funded by the ERC Advanced grant FUNGRAPH
No 788065 http://fungraph.inria.fr. The authors are grateful to Adobe
for generous donations, the OPAL infrastructure from Université
Côte d’Azur and for the HPC resources from GENCI–IDRIS (Grant
2022-AD011013409). The authors thank the anonymous reviewers
for their valuable feedback, P. Hedman and A. Tewari for proof-
reading earlier drafts also T. Müller, A. Yu and S. Fridovich-Keil for
helping with the comparisons.
ACM Trans. Graph., Vol. 42, No. 4, Article . Publication date: August 2023.


12
•
Bernhard Kerbl, Georgios Kopanas, Thomas Leimkühler, and George Drettakis
REFERENCES
Kara-Ali Aliev, Artem Sevastopolsky, Maria Kolos, Dmitry Ulyanov, and Victor Lem-
pitsky. 2020. Neural Point-Based Graphics. In Computer Vision – ECCV 2020: 16th
European Conference, Glasgow, UK, August 23–28, 2020, Proceedings, Part XXII. 696–
712.
Jonathan T Barron, Ben Mildenhall, Matthew Tancik, Peter Hedman, Ricardo Martin-
Brualla, and Pratul P Srinivasan. 2021. Mip-nerf: A multiscale representation for
anti-aliasing neural radiance fields. In Proceedings of the IEEE/CVF International
Conference on Computer Vision. 5855–5864.
Jonathan T. Barron, Ben Mildenhall, Dor Verbin, Pratul P. Srinivasan, and Peter Hedman.
2022. Mip-NeRF 360: Unbounded Anti-Aliased Neural Radiance Fields. CVPR (2022).
Sebastien Bonopera, Jerome Esnault, Siddhant Prakash, Simon Rodriguez, Theo Thonat,
Mehdi Benadel, Gaurav Chaurasia, Julien Philip, and George Drettakis. 2020. sibr:
A System for Image Based Rendering. https://gitlab.inria.fr/sibr/sibr_core
Mario Botsch, Alexander Hornung, Matthias Zwicker, and Leif Kobbelt. 2005. High-
Quality Surface Splatting on Today’s GPUs. In Proceedings of the Second Eurographics
/ IEEE VGTC Conference on Point-Based Graphics (New York, USA) (SPBG’05). Euro-
graphics Association, Goslar, DEU, 17–24.
Chris Buehler, Michael Bosse, Leonard McMillan, Steven Gortler, and Michael Cohen.
2001. Unstructured lumigraph rendering. In Proc. SIGGRAPH.
Gaurav Chaurasia, Sylvain Duchene, Olga Sorkine-Hornung, and George Drettakis.
2013. Depth synthesis and local warps for plausible image-based navigation. ACM
Transactions on Graphics (TOG) 32, 3 (2013), 1–12.
Anpei Chen, Zexiang Xu, Andreas Geiger, Jingyi Yu, and Hao Su. 2022b. TensoRF:
Tensorial Radiance Fields. In European Conference on Computer Vision (ECCV).
Zhiqin Chen, Thomas Funkhouser, Peter Hedman, and Andrea Tagliasacchi. 2022a.
MobileNeRF: Exploiting the Polygon Rasterization Pipeline for Efficient Neural Field
Rendering on Mobile Architectures. arXiv preprint arXiv:2208.00277 (2022).
Ricardo L De Queiroz and Philip A Chou. 2016. Compression of 3D point clouds using
a region-adaptive hierarchical transform. IEEE Transactions on Image Processing 25,
8 (2016), 3947–3956.
Martin Eisemann, Bert De Decker, Marcus Magnor, Philippe Bekaert, Edilson De Aguiar,
Naveed Ahmed, Christian Theobalt, and Anita Sellent. 2008. Floating textures. In
Computer graphics forum, Vol. 27. Wiley Online Library, 409–418.
John Flynn, Ivan Neulander, James Philbin, and Noah Snavely. 2016. Deepstereo:
Learning to predict new views from the world’s imagery. In CVPR.
Fridovich-Keil and Yu, Matthew Tancik, Qinhong Chen, Benjamin Recht, and Angjoo
Kanazawa. 2022. Plenoxels: Radiance Fields without Neural Networks. In CVPR.
Stephan J. Garbin, Marek Kowalski, Matthew Johnson, Jamie Shotton, and Julien
Valentin. 2021. FastNeRF: High-Fidelity Neural Rendering at 200FPS. In Proceedings
of the IEEE/CVF International Conference on Computer Vision (ICCV). 14346–14355.
Michael Goesele, Noah Snavely, Brian Curless, Hugues Hoppe, and Steven M Seitz.
2007. Multi-view stereo for community photo collections. In ICCV.
Steven J Gortler, Radek Grzeszczuk, Richard Szeliski, and Michael F Cohen. 1996. The
lumigraph. In Proceedings of the 23rd annual conference on Computer graphics and
interactive techniques. 43–54.
Markus Gross and Hanspeter (Eds) Pfister. 2011. Point-based graphics. Elsevier.
Jeff P. Grossman and William J. Dally. 1998. Point Sample Rendering. In Rendering
Techniques.
Peter Hedman, Julien Philip, True Price, Jan-Michael Frahm, George Drettakis, and
Gabriel Brostow. 2018. Deep blending for free-viewpoint image-based rendering.
ACM Trans. on Graphics (TOG) 37, 6 (2018).
Peter Hedman, Tobias Ritschel, George Drettakis, and Gabriel Brostow. 2016. Scalable
Inside-Out Image-Based Rendering. ACM Transactions on Graphics (SIGGRAPH
Asia Conference Proceedings) 35, 6 (December 2016). http://www-sop.inria.fr/reves/
Basilic/2016/HRDB16
Peter Hedman, Pratul P. Srinivasan, Ben Mildenhall, Jonathan T. Barron, and Paul
Debevec. 2021. Baking Neural Radiance Fields for Real-Time View Synthesis. ICCV
(2021).
Philipp Henzler, Niloy J Mitra, and Tobias Ritschel. 2019. Escaping plato’s cave: 3d shape
from adversarial rendering. In Proceedings of the IEEE/CVF International Conference
on Computer Vision. 9984–9993.
Arno Knapitsch, Jaesik Park, Qian-Yi Zhou, and Vladlen Koltun. 2017. Tanks and
temples: Benchmarking large-scale scene reconstruction. ACM Transactions on
Graphics (ToG) 36, 4 (2017), 1–13.
Georgios Kopanas, Thomas Leimkühler, Gilles Rainer, Clément Jambon, and George
Drettakis. 2022. Neural Point Catacaustics for Novel-View Synthesis of Reflections.
ACM Transactions on Graphics (SIGGRAPH Asia Conference Proceedings) 41, 6 (2022),
201. http://www-sop.inria.fr/reves/Basilic/2022/KLRJD22
Georgios Kopanas, Julien Philip, Thomas Leimkühler, and George Drettakis. 2021. Point-
Based Neural Rendering with Per-View Optimization. Computer Graphics Forum 40,
4 (2021), 29–43. https://doi.org/10.1111/cgf.14339
Samuli Laine and Tero Karras. 2011. High-performance software rasterization on GPUs.
In Proceedings of the ACM SIGGRAPH Symposium on High Performance Graphics.
79–88.
Christoph Lassner and Michael Zollhofer. 2021. Pulsar: Efficient Sphere-Based Neural
Rendering. In Proceedings of the IEEE/CVF Conference on Computer Vision and Pattern
Recognition (CVPR). 1440–1449.
Marc Levoy and Pat Hanrahan. 1996. Light field rendering. In Proceedings of the 23rd
annual conference on Computer graphics and interactive techniques. 31–42.
Stephen Lombardi, Tomas Simon, Gabriel Schwartz, Michael Zollhoefer, Yaser Sheikh,
and Jason Saragih. 2021. Mixture of volumetric primitives for efficient neural
rendering. ACM Transactions on Graphics (TOG) 40, 4 (2021), 1–13.
Duane G Merrill and Andrew S Grimshaw. 2010. Revisiting sorting for GPGPU stream
architectures. In Proceedings of the 19th international conference on Parallel architec-
tures and compilation techniques. 545–546.
Ben Mildenhall, Pratul P. Srinivasan, Matthew Tancik, Jonathan T. Barron, Ravi Ra-
mamoorthi, and Ren Ng. 2020. NeRF: Representing Scenes as Neural Radiance Fields
for View Synthesis. In ECCV.
Thomas Müller, Alex Evans, Christoph Schied, and Alexander Keller. 2022. Instant
Neural Graphics Primitives with a Multiresolution Hash Encoding. ACM Trans.
Graph. 41, 4, Article 102 (July 2022), 15 pages.
https://doi.org/10.1145/3528223.
3530127
Eric Penner and Li Zhang. 2017. Soft 3D reconstruction for view synthesis. ACM
Transactions on Graphics (TOG) 36, 6 (2017), 1–11.
Hanspeter Pfister, Matthias Zwicker, Jeroen van Baar, and Markus Gross. 2000. Surfels:
Surface Elements as Rendering Primitives. In Proceedings of the 27th Annual Con-
ference on Computer Graphics and Interactive Techniques (SIGGRAPH ’00). ACM
Press/Addison-Wesley Publishing Co., USA, 335–342.
https://doi.org/10.1145/
344779.344936
Christian Reiser, Songyou Peng, Yiyi Liao, and Andreas Geiger. 2021. KiloNeRF: Speed-
ing up Neural Radiance Fields with Thousands of Tiny MLPs. In International
Conference on Computer Vision (ICCV).
Liu Ren, Hanspeter Pfister, and Matthias Zwicker. 2002. Object Space EWA Surface
Splatting: A Hardware Accelerated Approach to High Quality Point Rendering.
Computer Graphics Forum 21 (2002).
Helge Rhodin, Nadia Robertini, Christian Richardt, Hans-Peter Seidel, and Christian
Theobalt. 2015. A versatile scene model with differentiable visibility applied to
generative pose estimation. In Proceedings of the IEEE International Conference on
Computer Vision. 765–773.
Gernot Riegler and Vladlen Koltun. 2020. Free view synthesis. In European Conference
on Computer Vision. Springer, 623–640.
Darius Rückert, Linus Franke, and Marc Stamminger. 2022. ADOP: Approximate
Differentiable One-Pixel Point Rendering. ACM Trans. Graph. 41, 4, Article 99 (jul
2022), 14 pages. https://doi.org/10.1145/3528223.3530122
Miguel Sainz and Renato Pajarola. 2004. Point-based rendering techniques. Computers
and Graphics 28, 6 (2004), 869–879. https://doi.org/10.1016/j.cag.2004.08.014
Johannes Lutz Schönberger and Jan-Michael Frahm. 2016. Structure-from-Motion
Revisited. In Conference on Computer Vision and Pattern Recognition (CVPR).
Markus Schütz, Bernhard Kerbl, and Michael Wimmer. 2022. Software Rasterization of
2 Billion Points in Real Time. Proc. ACM Comput. Graph. Interact. Tech. 5, 3, Article
24 (jul 2022), 17 pages. https://doi.org/10.1145/3543863
Vincent Sitzmann, Justus Thies, Felix Heide, Matthias Nießner, Gordon Wetzstein, and
Michael Zollhofer. 2019. Deepvoxels: Learning persistent 3d feature embeddings. In
Proceedings of the IEEE/CVF Conference on Computer Vision and Pattern Recognition.
2437–2446.
Noah Snavely, Steven M Seitz, and Richard Szeliski. 2006. Photo tourism: exploring
photo collections in 3D. In Proc. SIGGRAPH.
Carsten Stoll, Nils Hasler, Juergen Gall, Hans-Peter Seidel, and Christian Theobalt. 2011.
Fast articulated motion tracking using a sums of gaussians body model. In 2011
International Conference on Computer Vision. IEEE, 951–958.
Cheng Sun, Min Sun, and Hwann-Tzong Chen. 2022. Direct Voxel Grid Optimization:
Super-fast Convergence for Radiance Fields Reconstruction. In CVPR.
Towaki Takikawa, Alex Evans, Jonathan Tremblay, Thomas Müller, Morgan McGuire,
Alec Jacobson, and Sanja Fidler. 2022. Variable bitrate neural fields. In ACM SIG-
GRAPH 2022 Conference Proceedings. 1–9.
Towaki Takikawa, Joey Litalien, Kangxue Yin, Karsten Kreis, Charles Loop, Derek
Nowrouzezahrai, Alec Jacobson, Morgan McGuire, and Sanja Fidler. 2021. Neural
Geometric Level of Detail: Real-time Rendering with Implicit 3D Shapes. (2021).
Ayush Tewari, Justus Thies, Ben Mildenhall, Pratul Srinivasan, Edgar Tretschk, W Yifan,
Christoph Lassner, Vincent Sitzmann, Ricardo Martin-Brualla, Stephen Lombardi,
et al. 2022. Advances in neural rendering. In Computer Graphics Forum, Vol. 41.
Wiley Online Library, 703–735.
Justus Thies, Michael Zollhöfer, and Matthias Nießner. 2019. Deferred neural rendering:
Image synthesis using neural textures. ACM Transactions on Graphics (TOG) 38, 4
(2019), 1–12.
Angtian Wang, Peng Wang, Jian Sun, Adam Kortylewski, and Alan Yuille. 2023. VoGE: A
Differentiable Volume Renderer using Gaussian Ellipsoids for Analysis-by-Synthesis.
In The Eleventh International Conference on Learning Representations.
https://
openreview.net/forum?id=AdPJb9cud_Y
ACM Trans. Graph., Vol. 42, No. 4, Article . Publication date: August 2023.


3D Gaussian Splatting for Real-Time Radiance Field Rendering
•
13
Olivia Wiles, Georgia Gkioxari, Richard Szeliski, and Justin Johnson. 2020. Synsin:
End-to-end view synthesis from a single image. In Proceedings of the IEEE/CVF
Conference on Computer Vision and Pattern Recognition. 7467–7477.
Xiuchao Wu, Jiamin Xu, Zihan Zhu, Hujun Bao, Qixing Huang, James Tompkin, and
Weiwei Xu. 2022. Scalable Neural Indoor Scene Rendering. ACM Transactions on
Graphics (TOG) (2022).
Yiheng Xie, Towaki Takikawa, Shunsuke Saito, Or Litany, Shiqin Yan, Numair Khan,
Federico Tombari, James Tompkin, Vincent Sitzmann, and Srinath Sridhar. 2022.
Neural fields in visual computing and beyond. In Computer Graphics Forum, Vol. 41.
Wiley Online Library, 641–676.
Qiangeng Xu, Zexiang Xu, Julien Philip, Sai Bi, Zhixin Shu, Kalyan Sunkavalli, and
Ulrich Neumann. 2022. Point-nerf: Point-based neural radiance fields. In Proceedings
of the IEEE/CVF Conference on Computer Vision and Pattern Recognition. 5438–5448.
Wang Yifan, Felice Serena, Shihao Wu, Cengiz Öztireli, and Olga Sorkine-Hornung.
2019. Differentiable surface splatting for point-based geometry processing. ACM
Transactions on Graphics (TOG) 38, 6 (2019), 1–14.
Alex Yu, Ruilong Li, Matthew Tancik, Hao Li, Ren Ng, and Angjoo Kanazawa. 2021.
PlenOctrees for Real-time Rendering of Neural Radiance Fields. In ICCV.
Qiang Zhang, Seung-Hwan Baek, Szymon Rusinkiewicz, and Felix Heide. 2022. Dif-
ferentiable Point-Based Radiance Fields for Efficient View Synthesis. In SIGGRAPH
Asia 2022 Conference Papers (Daegu, Republic of Korea) (SA ’22). Association for
Computing Machinery, New York, NY, USA, Article 7, 12 pages. https://doi.org/10.
1145/3550469.3555413
Tinghui Zhou, Shubham Tulsiani, Weilun Sun, Jitendra Malik, and Alexei A Efros.
2016. View synthesis by appearance flow. In European conference on computer vision.
Springer, 286–301.
Matthias Zwicker, Hanspeter Pfister, Jeroen Van Baar, and Markus Gross. 2001a. EWA
volume splatting. In Proceedings Visualization, 2001. VIS’01. IEEE, 29–538.
Matthias Zwicker, Hanspeter Pfister, Jeroen van Baar, and Markus Gross. 2001b. Surface
Splatting. In Proceedings of the 28th Annual Conference on Computer Graphics and
Interactive Techniques (SIGGRAPH ’01). Association for Computing Machinery, New
York, NY, USA, 371–378. https://doi.org/10.1145/383259.383300
A
DETAILS OF GRADIENT COMPUTATION
Recall that Σ/Σ′ are the world/view space covariance matrices of
the Gaussian, 𝑞is the rotation, and 𝑠the scaling, 𝑊is the viewing
transformation and 𝐽the Jacobian of the affine approximation of
the projective transformation. We can apply the chain rule to find
the derivatives w.r.t. scaling and rotation:
𝑑Σ′
𝑑𝑠= 𝑑Σ′
𝑑Σ
𝑑Σ
𝑑𝑠
(8)
and
𝑑Σ′
𝑑𝑞= 𝑑Σ′
𝑑Σ
𝑑Σ
𝑑𝑞
(9)
Simplifying Eq. 5 using𝑈= 𝐽𝑊and Σ′ being the (symmetric) upper
left 2×2 matrix of𝑈Σ𝑈𝑇, denoting matrix elements with subscripts,
we can find the partial derivatives 𝜕Σ′
𝜕Σ𝑖𝑗=
 𝑈1,𝑖𝑈1,𝑗𝑈1,𝑖𝑈2,𝑗
𝑈1,𝑗𝑈2,𝑖𝑈2,𝑖𝑈2,𝑗

.
Next, we seek the derivatives 𝑑Σ
𝑑𝑠and 𝑑Σ
𝑑𝑞. Since Σ = 𝑅𝑆𝑆𝑇𝑅𝑇,
we can compute 𝑀= 𝑅𝑆and rewrite Σ = 𝑀𝑀𝑇. Thus, we can
write 𝑑Σ
𝑑𝑠=
𝑑Σ
𝑑𝑀
𝑑𝑀
𝑑𝑠and 𝑑Σ
𝑑𝑞=
𝑑Σ
𝑑𝑀
𝑑𝑀
𝑑𝑞. Since the covariance ma-
trix Σ (and its gradient) is symmetric, the shared first part is com-
pactly found by 𝑑Σ
𝑑𝑀= 2𝑀𝑇. For scaling, we further have 𝜕𝑀𝑖,𝑗
𝜕𝑠𝑘
=
 𝑅𝑖,𝑘
if j = k
0
otherwise

. To derive gradients for rotation, we recall the
conversion from a unit quaternion 𝑞with real part 𝑞𝑟and imaginary
parts 𝑞𝑖,𝑞𝑗,𝑞𝑘to a rotation matrix 𝑅:
𝑅(𝑞) = 2
©
­
­
«
1
2 −(𝑞2
𝑗+ 𝑞2
𝑘)
(𝑞𝑖𝑞𝑗−𝑞𝑟𝑞𝑘)
(𝑞𝑖𝑞𝑘+ 𝑞𝑟𝑞𝑗)
(𝑞𝑖𝑞𝑗+ 𝑞𝑟𝑞𝑘)
1
2 −(𝑞2
𝑖+ 𝑞2
𝑘)
(𝑞𝑗𝑞𝑘−𝑞𝑟𝑞𝑖)
(𝑞𝑖𝑞𝑘−𝑞𝑟𝑞𝑗)
(𝑞𝑗𝑞𝑘+ 𝑞𝑟𝑞𝑖)
1
2 −(𝑞2
𝑖+ 𝑞2
𝑗)
ª
®
®
¬
(10)
As a result, we find the following gradients for the components of 𝑞:
𝜕𝑀
𝜕𝑞𝑟
= 2

0
−𝑠𝑦𝑞𝑘𝑠𝑧𝑞𝑗
𝑠𝑥𝑞𝑘
0
−𝑠𝑧𝑞𝑖
−𝑠𝑥𝑞𝑗
𝑠𝑦𝑞𝑖
0

,
𝜕𝑀
𝜕𝑞𝑖
= 2

0
𝑠𝑦𝑞𝑗
𝑠𝑧𝑞𝑘
𝑠𝑥𝑞𝑗−2𝑠𝑦𝑞𝑖−𝑠𝑧𝑞𝑟
𝑠𝑥𝑞𝑘
𝑠𝑦𝑞𝑟
−2𝑠𝑧𝑞𝑖

𝜕𝑀
𝜕𝑞𝑗
= 2
 −2𝑠𝑥𝑞𝑗𝑠𝑦𝑞𝑖
𝑠𝑧𝑞𝑟
𝑠𝑥𝑞𝑖
0
𝑠𝑧𝑞𝑘
−𝑠𝑥𝑞𝑟𝑠𝑦𝑞𝑘−2𝑠𝑧𝑞𝑗

,
𝜕𝑀
𝜕𝑞𝑘
= 2
 −2𝑠𝑥𝑞𝑘−𝑠𝑦𝑞𝑟𝑠𝑧𝑞𝑖
𝑠𝑥𝑞𝑟
−2𝑠𝑦𝑞𝑘𝑠𝑧𝑞𝑗
𝑠𝑥𝑞𝑖
𝑠𝑦𝑞𝑗
0

(11)
Deriving gradients for quaternion normalization is straightforward.
B
OPTIMIZATION AND DENSIFICATION ALGORITHM
Our optimization and densification algorithms are summarized in
Algorithm 1.
Algorithm 1 Optimization and Densification
𝑤, ℎ: width and height of the training images
𝑀←SfM Points
⊲Positions
𝑆,𝐶,𝐴←InitAttributes()
⊲Covariances, Colors, Opacities
𝑖←0
⊲Iteration Count
while not converged do
𝑉, ˆ
𝐼←SampleTrainingView()
⊲Camera 𝑉and Image
𝐼←Rasterize(𝑀, 𝑆, 𝐶, 𝐴, 𝑉)
⊲Alg. 2
𝐿←𝐿𝑜𝑠𝑠(𝐼, ˆ
𝐼)
⊲Loss
𝑀, 𝑆, 𝐶, 𝐴←Adam(∇𝐿)
⊲Backprop & Step
if IsRefinementIteration(𝑖) then
for all Gaussians (𝜇, Σ,𝑐, 𝛼) in (𝑀,𝑆,𝐶,𝐴) do
if 𝛼< 𝜖or IsTooLarge(𝜇, Σ) then
⊲Pruning
RemoveGaussian()
end if
if ∇𝑝𝐿> 𝜏𝑝then
⊲Densification
if ∥𝑆∥> 𝜏𝑆then
⊲Over-reconstruction
SplitGaussian(𝜇, Σ,𝑐, 𝛼)
else
⊲Under-reconstruction
CloneGaussian(𝜇, Σ,𝑐, 𝛼)
end if
end if
end for
end if
𝑖←𝑖+ 1
end while
C
DETAILS OF THE RASTERIZER
Sorting. Our design is based on the assumption of a high load
of small splats, and we optimize for this by sorting splats once for
each frame using radix sort at the beginning. We split the screen
into 16x16 pixel tiles (or bins). We create a list of splats per tile by
instantiating each splat in each 16×16 tile it overlaps. This results
in a moderate increase in Gaussians to process which however is
amortized by simpler control flow and high parallelism of optimized
GPU Radix sort [Merrill and Grimshaw 2010]. We assign a key for
each splats instance with up to 64 bits where the lower 32 bits
encode its projected depth and the higher bits encode the index of
the overlapped tile. The exact size of the index depends on how
many tiles fit the current resolution. Depth ordering is thus directly
resolved for all splats in parallel with a single radix sort. After
ACM Trans. Graph., Vol. 42, No. 4, Article . Publication date: August 2023.


14
•
Bernhard Kerbl, Georgios Kopanas, Thomas Leimkühler, and George Drettakis
sorting, we can efficiently produce per-tile lists of Gaussians to
process by identifying the start and end of ranges in the sorted
array with the same tile ID. This is done in parallel, launching
one thread per 64-bit array element to compare its higher 32 bits
with its two neighbors. Compared to [Lassner and Zollhofer 2021],
our rasterization thus completely eliminates sequential primitive
processing steps and produces more compact per-tile lists to traverse
during the forward pass. We show a high-level overview of the
rasterization approach in Algorithm 2.
Algorithm 2 GPU software rasterization of 3D Gaussians
𝑤, ℎ: width and height of the image to rasterize
𝑀, 𝑆: Gaussian means and covariances in world space
𝐶, 𝐴: Gaussian colors and opacities
𝑉: view configuration of current camera
function Rasterize(𝑤, ℎ, 𝑀, 𝑆, 𝐶, 𝐴, 𝑉)
CullGaussian(𝑝, 𝑉)
⊲Frustum Culling
𝑀′,𝑆′ ←ScreenspaceGaussians(𝑀, 𝑆, 𝑉)
⊲Transform
𝑇←CreateTiles(𝑤, ℎ)
𝐿, 𝐾←DuplicateWithKeys(𝑀′, 𝑇)
⊲Indices and Keys
SortByKeys(𝐾, 𝐿)
⊲Globally Sort
𝑅←IdentifyTileRanges(𝑇, 𝐾)
𝐼←0
⊲Init Canvas
for all Tiles 𝑡in 𝐼do
for all Pixels 𝑖in 𝑡do
𝑟←GetTileRange(𝑅, 𝑡)
𝐼[𝑖] ←BlendInOrder(𝑖, 𝐿, 𝑟, 𝐾, 𝑀′, 𝑆′, 𝐶, 𝐴)
end for
end for
return 𝐼
end function
Numerical stability. During the backward pass, we reconstruct
the intermediate opacity values needed for gradient computation by
repeatedly dividing the accumulated opacity from the forward pass
by each Gaussian’s 𝛼. Implemented naïvely, this process is prone to
numerical instabilities (e.g., division by 0). To address this, both in
the forward and backward pass, we skip any blending updates with
𝛼< 𝜖(we choose 𝜖as
1
255) and also clamp 𝛼with 0.99 from above.
Finally, before a Gaussian is included in the forward rasterization
pass, we compute the accumulated opacity if we were to include it
and stop front-to-back blending before it can exceed 0.9999.
D
PER-SCENE ERROR METRICS
Tables 4–9 list the various collected error metrics for our evaluation
over all considered techniques and real-world scenes. We list both
the copied Mip-NeRF360 numbers and those of our runs used to
generate the images in the paper; averages for these over the full
Mip-NeRF360 dataset are PSNR 27.58, SSIM 0.790, and LPIPS 0.240.
Table 4. SSIM scores for Mip-NeRF360 scenes. † copied from original paper.
bicycle
flowers
garden
stump
treehill
room
counter
kitchen
bonsai
Plenoxels
0.496
0.431
0.6063
0.523
0.509
0.8417
0.759
0.648
0.814
INGP-Base
0.491
0.450
0.649
0.574
0.518
0.855
0.798
0.818
0.890
INGP-Big
0.512
0.486
0.701
0.594
0.542
0.871
0.817
0.858
0.906
Mip-NeRF360†
0.685
0.583
0.813
0.744
0.632
0.913
0.894
0.920
0.941
Mip-NeRF360
0.685
0.584
0.809
0.745
0.631
0.910
0.892
0.917
0.938
Ours-7k
0.675
0.525
0.836
0.728
0.598
0.884
0.873
0.900
0.910
Ours-30k
0.771
0.605
0.868
0.775
0.638
0.914
0.905
0.922
0.938
Table 5. PSNR scores for Mip-NeRF360 scenes. † copied from original paper.
bicycle
flowers
garden
stump
treehill
room
counter
kitchen
bonsai
Plenoxels
21.912
20.097
23.4947
20.661
22.248
27.594
23.624
23.420
24.669
INGP-Base
22.193
20.348
24.599
23.626
22.364
29.269
26.439
28.548
30.337
INGP-Big
22.171
20.652
25.069
23.466
22.373
29.690
26.691
29.479
30.685
Mip-NeRF360†
24.37
21.73
26.98
26.40
22.87
31.63
29.55
32.23
33.46
Mip-NeRF360
24.305
21.649
26.875
26.175
22.929
31.467
29.447
31.989
33.397
Ours-7k
23.604
20.515
26.245
25.709
22.085
28.139
26.705
28.546
28.850
Ours-30k
25.246
21.520
27.410
26.550
22.490
30.632
28.700
30.317
31.980
Table 6. LPIPS scores for Mip-NeRF360 scenes. † copied from original paper.
bicycle
flowers
garden
stump
treehill
room
counter
kitchen
bonsai
Plenoxels
0.506
0.521
0.3864
0.503
0.540
0.4186
0.441
0.447
0.398
INGP-Base
0.487
0.481
0.312
0.450
0.489
0.301
0.342
0.254
0.227
INGP-Big
0.446
0.441
0.257
0.421
0.450
0.261
0.306
0.195
0.205
Mip-NeRF360†
0.301
0.344
0.170
0.261
0.339
0.211
0.204
0.127
0.176
Mip-NeRF360
0.305
0.346
0.171
0.265
0.347
0.213
0.207
0.128
0.179
Ours-7k
0.318
0.417
0.153
0.287
0.404
0.272
0.254
0.161
0.244
Ours-30k
0.205
0.336
0.103
0.210
0.317
0.220
0.204
0.129
0.205
Table 7. SSIM scores for Tanks&Temples and Deep Blending scenes.
Truck
Train
Dr Johnson
Playroom
Plenoxels
0.774
0.663
0.787
0.802
INGP-Base
0.779
0.666
0.839
0.754
INGP-Big
0.800
0.689
0.854
0.779
Mip-NeRF360
0.857
0.660
0.901
0.900
Ours-7k
0.840
0.694
0.853
0.896
Ours-30k
0.879
0.802
0.899
0.906
Table 8. PSNR scores for Tanks&Temples and Deep Blending scenes.
Truck
Train
Dr Johnson
Playroom
Plenoxels
23.221
18.927
23.142
22.980
INGP-Base
23.260
20.170
27.750
19.483
INGP-Big
23.383
20.456
28.257
21.665
Mip-NeRF360
24.912
19.523
29.140
29.657
Ours-7k
23.506
18.892
26.306
29.245
Ours-30k
25.187
21.097
28.766
30.044
Table 9. LPIPS scores for Tanks&Temples and Deep Blending scenes.
Truck
Train
Dr Johnson
Playroom
Plenoxels
0.335
0.422
0.521
0.499
INGP-Base
0.274
0.386
0.381
0.465
INGP-Big
0.249
0.360
0.352
0.428
Mip-NeRF360
0.159
0.354
0.237
0.252
Ours-7k
0.209
0.350
0.343
0.291
Ours-30k
0.148
0.218
0.244
0.241
ACM Trans. Graph., Vol. 42, No. 4, Article . Publication date: August 2023.


2D Gaussian Splatting for Geometrically Accurate Radiance Fields
BINBIN HUANG, ShanghaiTech University, China
ZEHAO YU, University of Tübingen, Tübingen AI Center, Germany
ANPEI CHEN, University of Tübingen, Tübingen AI Center, Germany
ANDREAS GEIGER, University of Tübingen, Tübingen AI Center, Germany
SHENGHUA GAO, ShanghaiTech University, China
https://surfsplatting.github.io
Mesh
Radiance field
Disk (color)
Disk (normal)
Surface normal
(a) 2D disks as surface elements
(b) 2D Gaussian splatting
(c) Meshing
Fig. 1. Our method, 2DGS, (a) optimizes a set of 2D oriented disks to represent and reconstruct a complex real-world scene from multi-view RGB images. These
optimized 2D disks are tightly aligned to the surfaces. (b) With 2D Gaussian splatting, we allow real-time rendering of high quality novel view images with
view consistent normals and depth maps. (c) Finally, our method provides detailed and noise-free triangle mesh reconstruction from the optimized 2D disks.
3D Gaussian Splatting (3DGS) has recently revolutionized radiance field
reconstruction, achieving high quality novel view synthesis and fast render-
ing speed. However, 3DGS fails to accurately represent surfaces due to the
multi-view inconsistent nature of 3D Gaussians. We present 2D Gaussian
Splatting (2DGS), a novel approach to model and reconstruct geometrically
accurate radiance fields from multi-view images. Our key idea is to collapse
the 3D volume into a set of 2D oriented planar Gaussian disks. Unlike 3D
Gaussians, 2D Gaussians provide view-consistent geometry while modeling
surfaces intrinsically. To accurately recover thin surfaces and achieve stable
optimization, we introduce a perspective-accurate 2D splatting process uti-
lizing ray-splat intersection and rasterization. Additionally, we incorporate
depth distortion and normal consistency terms to further enhance the quality
of the reconstructions. We demonstrate that our differentiable renderer al-
lows for noise-free and detailed geometry reconstruction while maintaining
competitive appearance quality, fast training speed, and real-time rendering.
Our code will be made publicly available.
CCS Concepts: • Computing methodologies →Reconstruction; Render-
ing; Machine learning approaches.
Additional Key Words and Phrases: novel view synthesis, radiance fields,
surface splatting, surface reconstruction
Authors’ addresses: Binbin Huang, ShanghaiTech University, China; Zehao Yu, Univer-
sity of Tübingen, Tübingen AI Center, Germany; Anpei Chen, University of Tübingen,
Tübingen AI Center, Germany; Andreas Geiger, University of Tübingen, Tübingen AI
Center, Germany; Shenghua Gao, ShanghaiTech University, China.
1
INTRODUCTION
Photorealistic novel view synthesis (NVS) and accurate geometry
reconstruction stand as pivotal long-term objectives in computer
graphics and vision. Recently, 3D Gaussian Splatting (3DGS) [Kerbl
et al. 2023] has emerged as an appealing alternative to implicit [Bar-
ron et al. 2022a; Mildenhall et al. 2020] and feature grid-based rep-
resentations [Barron et al. 2023; Müller et al. 2022] in NVS, due to
its real-time photorealistic NVS results at high resolutions. Rapidly
evolving, 3DGS has been quickly extended with respect to multiple
domains, including anti-aliasing rendering [Yu et al. 2024], material
modeling [Jiang et al. 2023; Shi et al. 2023], dynamic scene recon-
struction [Yan et al. 2023], and animatable avatar creation [Qian
et al. 2023; Zielonka et al. 2023]. Nevertheless, it falls short in cap-
turing intricate geometry since the volumetric 3D Gaussian, which
models the complete angular radiance, conflicts with the thin nature
of surfaces.
On the other hand, earlier works [Pfister et al. 2000; Zwicker et al.
2001a] have shown surfels (surface elements) to be an effective rep-
resentation for complex geometry. Surfels approximate the object
surface locally with shape and shade attributes, and can be derived
from known geometry. They are widely used in SLAM [Whelan et al.
arXiv:2403.17888v1  [cs.CV]  26 Mar 2024


2
•
Binbin Huang, Zehao Yu, Anpei Chen, Andreas Geiger, and Shenghua Gao
2016] and other robotics tasks [Schöps et al. 2019] as an efficient ge-
ometry representation. Subsequent advancements [Yifan et al. 2019]
have incorporated surfels into a differentiable framework. However,
these methods typically require ground truth (GT) geometry, depth
sensor data, or operate under constrained scenarios with known
lighting.
Inspired by these works, we propose 2D Gaussian Splatting for
3D scene reconstruction and novel view synthesis that combines
the benefits of both worlds, while overcoming their limitations. Un-
like 3DGS, our approach represents a 3D scene with 2D Gaussian
primitives, each defining an oriented elliptical disk. The significant
advantage of 2D Gaussian over its 3D counterpart lies in the accu-
rate geometry representation during rendering. Specifically, 3DGS
evaluates a Gaussian’s value at the intersection between a pixel ray
and a 3D Gaussian [Keselman and Hebert 2022, 2023], which leads
to inconsistency depth when rendered from different viewpoints.
In contrast, our method utilizes explicit ray-splat intersection, re-
sulting in a perspective accuracy splatting, as illustrated in Figure 2,
which in turn significantly improves reconstruction quality. Fur-
thermore, the inherent surface normals in 2D Gaussian primitives
enable direct surface regularization through normal constraints. In
contrast with surfels-based models [Pfister et al. 2000; Yifan et al.
2019; Zwicker et al. 2001a], our 2D Gaussians can be recovered from
unknown geometry with gradient-based optimization.
While our 2D Gaussian approach excels in geometric model-
ing, optimizing solely with photometric losses can lead to noisy
reconstructions, due to the inherently unconstrained nature of 3D
reconstruction tasks, as noted in [Barron et al. 2022b; Yu et al. 2022b;
Zhang et al. 2020]. To enhance reconstructions and achieve smoother
surfaces, we introduce two regularization terms: depth distortion
and normal consistency. The depth distortion term concentrates 2D
primitives distributed within a tight range along the ray, address-
ing the rendering process’s limitation where the distance between
Gaussians is ignored. The normal consistency term minimizes dis-
crepancies between the rendered normal map and the gradient of
the rendered depth, ensuring alignment between the geometries
defined by depth and normals. Employing these regularizations
in combination with our 2D Gaussian model enables us to extract
highly accurate surface meshes, as demonstrated in Figure 1.
In summary, we make the following contributions:
• We present a highly efficient differentiable 2D Gaussian ren-
derer, enabling perspective-accurate splatting by leveraging
2D surface modeling, ray-splat intersection, and volumetric
integration.
• We introduce two regularization losses for improved and
noise-free surface reconstruction.
• Our approach achieves state-of-the-art geometry reconstruc-
tion and NVS results compared to other explicit representa-
tions.
2
RELATED WORK
2.1
Novel view synthesis
Significant advancements have been achieved in NVS, particularly
since the introduction of Neural Radiance Fields (NeRF) [Milden-
hall et al. 2021]. NeRF employs a multi-layer perceptron (MLP) to
Fig. 2. Comparison of 3DGS and 2DGS. 3DGS utilizes different intersec-
tion planes for value evaluation when viewing from different viewpoints,
resulting in inconsistency. Our 2DGS provides multi-view consistent value
evaluations.
represent geometry and view-dependent appearance, optimized via
volume rendering to deliver exceptional rendering quality. Post-
NeRF developments have further enhanced its capabilities. For in-
stance, Mip-NeRF [Barron et al. 2021] and subsequent works [Barron
et al. 2022a, 2023; Hu et al. 2023] tackle NeRF’s aliasing issues. Ad-
ditionally, the rendering efficiency of NeRF has seen substantial
improvements through techniques such as distillation [Reiser et al.
2021; Yu et al. 2021] and baking [Chen et al. 2023a; Hedman et al.
2021; Reiser et al. 2023; Yariv et al. 2023]. Moreover, the training
and representational power of NeRF have been enhanced using
feature-grid based scene representations [Chen et al. 2022, 2023c;
Fridovich-Keil et al. 2022; Liu et al. 2020; Müller et al. 2022; Sun et al.
2022a].
Recently, 3D Gaussian Splatting (3DGS) [Kerbl et al. 2023] has
emerged, demonstrating impressive real-time NVS results. This
method has been quickly extended to multiple domains [Xie et al.
2023; Yan et al. 2023; Yu et al. 2024; Zielonka et al. 2023]. In this work,
we propose to “flatten” 3D Gaussians to 2D Gaussian primitives to
better align their shape with the object surface. Combined with
two novel regularization losses, our approach reconstructs surfaces
more accurately than 3DGS while preserving its high-quality and
real-time rendering capabilities.
2.2
3D reconstruction
3D Reconstruction from multi-view images has been a long-standing
goal in computer vision. Multi-view stereo based methods [Schön-
berger et al. 2016; Yao et al. 2018; Yu and Gao 2020] rely on a modular
pipeline that involves feature matching, depth prediction, and fu-
sion. In contrast, recent neural approaches [Niemeyer et al. 2020;
Yariv et al. 2020] represent surface implicilty via an MLP [Mescheder
et al. 2019; Park et al. 2019] , extracting surfaces post-training via
the Marching Cube algorithm. Further advancements [Oechsle et al.
2021; Wang et al. 2021; Yariv et al. 2021] integrated implicit surfaces
with volume rendering, achieving detailed surface reconstructions
from RGB images. These methods have been extended to large-scale
reconstructions via additional regularization [Li et al. 2023; Yu et al.
2022a,b], and efficient reconstruction for objects [Wang et al. 2023].
Despite these impressive developments, efficient large-scale scene
reconstruction remains a challenge. For instance, Neuralangelo [Li
et al. 2023] requires 128 GPU hours for reconstructing a single scene
from the Tanks and Temples Dataset [Knapitsch et al. 2017]. In this
work, we introduce 2D Gaussian splatting, a method that signifi-
cantly accelerates the reconstruction process. It achieves similar or


2D Gaussian Splatting for Geometrically Accurate Radiance Fields
•
3
slightly better results compared to previous implicit neural surface
representations, while being an order of magnitude faster.
2.3
Differentiable Point-based Graphics
Differentiable point-based rendering [Aliev et al. 2020; Insafutdinov
and Dosovitskiy 2018; Rückert et al. 2022; Wiles et al. 2020; Yifan
et al. 2019]has been explored extensively due to its efficiency and
flexibility in representing intricate structures. Notably, NPBG [Aliev
et al. 2020] rasterizes point cloud features onto an image plane,
subsequently utilizing a convolutional neural network for RGB
image prediction. DSS [Yifan et al. 2019] focuses on optimizing ori-
ented point clouds from multi-view images under known lighting
conditions. Pulsar [Lassner and Zollhofer 2021] introduces a tile-
based acceleration structure for more efficient rasterization. More
recently, 3DGS [Kerbl et al. 2023] optimizes anisotropic 3D Gauss-
ian primitives, demonstrating real-time photorealistic NVS results.
Despite these advances, using point-based representations from un-
constrained multi-view images remains challenging. In this paper,
we demonstrate detailed surface reconstruction using 2D Gaussian
primitives. We also highlight the critical role of additional regular-
ization losses in optimization, showcasing their significant impact
on the quality of the reconstruction.
2.4
Concurrent work
Since 3DGS [Kerbl et al. 2023] was introduced, it has been rapidly
adapted across multiple domains. We now review the closest work
in inverse rendering. These work [Gao et al. 2023; Jiang et al. 2023;
Liang et al. 2023; Shi et al. 2023] extend 3DGS by modeling normals
as additional attributes of 3D Gaussian primitives. Our approach,
in contrast, inherently defines normals by representing the tangent
space of the 3D surface using 2D Gaussian primitives, aligning them
more closely with the underlying geometry. Additionally, the afore-
mentioned works predominantly focus on estimating the material
properties of the scene and evaluating their results for relighting
tasks. Notably, none of these works specifically target surface re-
construction, the primary focus of our work.
We also highlight the distinctions between our method and con-
current works SuGaR [Guédon and Lepetit 2023] and NeuSG [Chen
et al. 2023b]. Unlike SuGaR, which approximates 2D Gaussians with
3D Gaussians, our method directly employs 2D Gaussians, simpli-
fying the process and enhancing the resulting geometry without
additional mesh refinement. NeuSG optimizes 3D Gaussian primi-
tives and an implicit SDF network jointly and extracts the surface
from the SDF network, while our approach leverages 2D Gaussian
primitives for surface approximation, offering a faster and concep-
tually simpler solution.
3
3D GAUSSIAN SPLATTING
Kerbl et al. [Kerbl et al. 2023] propose to represent 3D scenes with
3D Gaussian primitives and render images using differentiable vol-
ume splatting. Specifically, 3DGS explicitly parameterizes Gaussian
primitives via 3D covariance matrix 𝚺and their location p𝑘:
G(p) = exp(−1
2 (p −p𝑘)⊤𝚺−1(p −p𝑘))
(1)
where the covariance matrix 𝚺= RSS⊤R⊤is factorized into a scal-
ing matrix S and a rotation matrix R. To render an image, the 3D
Gaussian is transformed into the camera coordinates with world-
to-camera transform matrix W and projected to image plane via a
local affine transformation J [Zwicker et al. 2001a]:
𝚺
′ = JW𝚺W⊤J⊤
(2)
By skipping the third row and column of 𝚺
′, we obtain a 2D Gaussian
G2𝐷with covariance matrix 𝚺2𝐷. Next, 3DGS [Kerbl et al. 2023]
employs volumetric alpha blending to integrate alpha-weighted
appearance from front to back:
c(x) =
𝐾
∑︁
𝑘=1
c𝑘𝛼𝑘G2𝐷
𝑘
(x)
𝑘−1
Ö
𝑗=1
(1 −𝛼𝑗G2𝐷
𝑗
(x))
(3)
where 𝑘is the index of the Gaussian primitives, 𝛼𝑘denotes the alpha
values and c𝑘is the view-dependent appearance. The attributes of
3D Gaussian primitives are optimized using a photometric loss.
Challenges in Surface Reconstruction: Reconstructing surfaces
using 3D Gaussian modeling and splatting faces several challenges.
First, the volumetric radiance representation of 3D Gaussians con-
flicts with the thin nature of surfaces. Second, 3DGS does not na-
tively model surface normals, essential for high-quality surface
reconstruction. Third, the rasterization process in 3DGS lacks multi-
view consistency, leading to varied 2D intersection planes for dif-
ferent viewpoints [Keselman and Hebert 2023], as illustrated in
Figure 2 (a). Additionally, using an affine matrix for transforming a
3D Gaussian into ray space only yields accurate projections near the
center, compromising on perspective accuracy around surrounding
regions [Zwicker et al. 2004]. Therefore, it often results in noisy
reconstructions, as shown in Figure 5.
4
2D GAUSSIAN SPLATTING
To accurately reconstruct geometry while maintaining high-quality
novel view synthesis, we present differentiable 2D Gaussian splat-
ting (2DGS).
4.1
Modeling
Unlike 3DGS [Kerbl et al. 2023], which models the entire angular
radiance in a blob, we simplify the 3-dimensional modeling by adopt-
ing “flat” 2D Gaussians embedded in 3D space. With 2D Gaussian
modeling, the primitive distributes densities within a planar disk,
defining the normal as the direction of steepest change of density.
This feature enables better alignment with thin surfaces. While pre-
vious methods [Kopanas et al. 2021; Yifan et al. 2019] also utilize 2D
Gaussians for geometry reconstruction, they require a dense point
cloud or ground-truth normals as input. By contrast, we simultane-
ously reconstruct the appearance and geometry given only a sparse
calibration point cloud and photometric supervision.
As illustrated in Figure 3, our 2D splat is characterized by its
central point p𝑘, two principal tangential vectors t𝑢and t𝑣, and
a scaling vector S = (𝑠𝑢,𝑠𝑣) that controls the variances of the 2D
Gaussian. Notice that the primitive normal is defined by two orthog-
onal tangential vectors t𝑤= t𝑢× t𝑣. We can arrange the orientation
into a 3 × 3 rotation matrix R = [t𝑢, t𝑣, t𝑤] and the scaling factors
into a 3 × 3 diagonal matrix S whose last entry is zero.


4
•
Binbin Huang, Zehao Yu, Anpei Chen, Andreas Geiger, and Shenghua Gao
𝑠!𝐭!
𝑠"𝐭"
2D Gaussian Splat 
in object space
2D Gaussian Splat 
in image space
Tangent frame (u,v)
Image frame (x,y)
𝐩!
𝑠"𝐭"
𝑠#𝐭#
Fig. 3. Illustration of 2D Gaussian Splatting. 2D Gaussian Splats are ellip-
tical disks characterized by a center point p𝑘, tangential vectors t𝑢and
t𝑣, and two scaling factors (𝑠𝑢and 𝑠𝑣) control the variance. Their elliptical
projections are sampled through the ray-splat intersection ( Section 4.2) and
accumulated via alpha-blending in image space. 2DGS reconstructs surface
attributes such as colors, depths, and normals through gradient descent.
A 2D Gaussian is therefore defined in a local tangent plane in
world space, which is parameterized:
𝑃(𝑢, 𝑣) = p𝑘+ 𝑠𝑢t𝑢𝑢+ 𝑠𝑣t𝑣𝑣= H(𝑢, 𝑣, 1, 1)⊤
(4)
where H =
𝑠𝑢t𝑢
𝑠𝑣t𝑣
0
p𝑘
0
0
0
1

=
RS
p𝑘
0
1

(5)
where H ∈4 × 4 is a homogeneous transformation matrix repre-
senting the geometry of the 2D Gaussian. For the point u = (𝑢, 𝑣) in
𝑢𝑣space, its 2D Gaussian value can then be evaluated by standard
Gaussian
G(u) = exp

−𝑢2 + 𝑣2
2

(6)
The center p𝑘, scaling (𝑠𝑢,𝑠𝑣), and the rotation (t𝑢, t𝑣) are learnable
parameters. Following 3DGS [Kerbl et al. 2023], each 2D Gaussian
primitive has opacity 𝛼and view-dependent appearance 𝑐parame-
terized with spherical harmonics.
4.2
Splatting
One common strategy for rendering 2D Gaussians is to project the
2D Gaussian primitives onto the image space using the affine ap-
proximation for the perspective projection [Zwicker et al. 2001a].
However, as noted in [Zwicker et al. 2004], this projection is only
accurate at the center of the Gaussian and has increasing approxi-
mation error with increased distance to the center. To address this
issue, Zwicker et al. proposed a formulation based on homogeneous
coordinates. Specifically, projecting the 2D splat onto an image plane
can be described by a general 2D-to-2D mapping in homogeneous
coordinates. Let W ∈4 × 4 be the transformation matrix from world
space to screen space. The screen space points are hence obtained
by
x = (𝑥𝑧,𝑦𝑧,𝑧,𝑧)⊤= W𝑃(𝑢, 𝑣) = WH(𝑢, 𝑣, 1, 1)⊤
(7)
where x represents a homogeneous ray emitted from the camera and
passing through pixel (𝑥,𝑦) and intersecting the splat at depth 𝑧. To
rasterize a 2D Gaussian, Zwicker et al. proposed to project its conic
into the screen space with an implicit method using M = (WH)−1.
However, the inverse transformation introduces numerical insta-
bility especially when the splat degenerates into a line segment
(i.e., if it is viewed from the side). To address this issue, previous
surface splatting rendering methods discard such ill-conditioned
transformations using a pre-defined threshold. However, such a
scheme poses challenges within a differentiable rendering frame-
work, as thresholding can lead to unstable optimization. To address
this problem, we utilize an explicit ray-splat intersection inspired
by [Sigg et al. 2006].
Ray-splat Intersection: We efficiently locate the ray-splat inter-
sections by finding the intersection of three non-parallel planes, a
method initially designed for specialized hardware [Weyrich et al.
2007]. Given an image coordinate x = (𝑥,𝑦), we parameterize the
ray of a pixel as the intersection of two orthogonal planes: the
x-plane and the y-plane. Specifically, the x-plane is defined by a
normal vector (−1, 0, 0) and an offset 𝑥. Therefore, the x-plane can
be represented as a 4D homogeneous plane h𝑥= (−1, 0, 0,𝑥). Sim-
ilarly, the y-plane is h𝑦= (0, −1, 0,𝑦). Thus, the ray x = (𝑥,𝑦) is
determined by the intersection of the 𝑥-plane and the 𝑦-planes.
Next, we transform both planes into the local coordinates of
the 2D Gaussian primitives, the 𝑢𝑣-coordinate system. Note that
transforming points on a plane using a transformation matrix M
is equivalent to transforming the homogeneous plane parameters
using the inverse transpose M−⊤[Vince 2008]. Therefore, applying
M = (WH)−1 is equivalent to (WH)⊤, eliminating explicit matrix
inversion and yielding:
h𝑢= (WH)⊤h𝑥
h𝑣= (WH)⊤h𝑦
(8)
As introduced in Section 4.1, points on the 2D Gaussian plane are
represented as (𝑢, 𝑣, 1, 1). At the same time, the intersection point
should fall on the transformed 𝑥-plane and 𝑦-plane. Thus,
h𝑢· (𝑢, 𝑣, 1, 1)⊤= h𝑣· (𝑢, 𝑣, 1, 1)⊤= 0
(9)
This leads to an efficient solution for the intersection point u(x):
𝑢(x) = h2
𝑢h4
𝑣−h4
𝑢h2
𝑣
h1
𝑢h2
𝑣−h2
𝑢h1
𝑣
𝑣(x) = h4
𝑢h1
𝑣−h1
𝑢h4
𝑣
h1
𝑢h2
𝑣−h2
𝑢h1
𝑣
(10)
where h𝑖
𝑢, h𝑖
𝑣are the 𝑖-th parameters of the 4D homogeneous plane
parameters. We obtain the depth 𝑧of the intersected points via Eq. 7
and evaluate the Gaussian value with Eq 6.
Degenerate Solutions: When a 2D Gaussian is observed from a
slanted viewpoint, it degenerates to a line in screen space. Therefore,
it might be missed during rasterization. To deal with these cases and
stabilize optimization, we employ the object-space low-pass filter
introduced in [Botsch et al. 2005]:
ˆ
G(x) = max
n
G(u(x)), G( x −c
𝜎
)
o
(11)
where u(x) is given by (10) and c is the projection of center p𝑘.
Intuitively, ˆ
G(x) is lower-bounded by a fixed screen-space Gaussian
low-pass filter with center c𝑘and radius 𝜎. In our experiments, we
set 𝜎=
√
2/2 to ensure sufficient pixels are used during rendering.
Rasterization: We follow a similar rasterization process as in
3DGS [Kerbl et al. 2023]. First, a screen space bounding box is com-
puted for each Gaussian primitive. Then, 2D Gaussians are sorted
based on the depth of their center and organized into tiles based on
their bounding boxes. Finally, volumetric alpha blending is used to


2D Gaussian Splatting for Geometrically Accurate Radiance Fields
•
5
integrate alpha-weighted appearance from front to back:
c(x) =
∑︁
𝑖=1
c𝑖𝛼𝑖ˆ
G𝑖(u(x))
𝑖−1
Ö
𝑗=1
(1 −𝛼𝑗ˆ
G𝑗(u(x)))
(12)
The iterative process is terminated when the accumulated opacity
reaches saturation.
5
TRAINING
Our 2D Gaussian method, while effective in geometric modeling, can
result in noisy reconstructions when optimized only with photomet-
ric losses, a challenge inherent to 3D reconstruction tasks [Barron
et al. 2022b; Yu et al. 2022b; Zhang et al. 2020]. To mitigate this
issue and improve the geometry reconstruction, we introduce two
regularization terms: depth distortion and normal consistency.
Depth Distortion: Different from NeRF, 3DGS’s volume rendering
doesn’t consider the distance between intersected Gaussian primi-
tives. Therefore, spread out Gaussians might result in a similar color
and depth rendering. This is different from surface rendering, where
rays intersect the first visible surface exactly once. To mitigate this
issue, we take inspiration from Mip-NeRF360 [Barron et al. 2022a]
and propose a depth distortion loss to concentrate the weight dis-
tribution along the rays by minimizing the distance between the
ray-splat intersections:
L𝑑=
∑︁
𝑖,𝑗
𝜔𝑖𝜔𝑗|𝑧𝑖−𝑧𝑗|
(13)
where 𝜔𝑖= 𝛼𝑖ˆ
G𝑖(u(x)) Î𝑖−1
𝑗=1(1 −𝛼𝑗ˆ
G𝑗(u(x))) is the blending
weight of the 𝑖−th intersection and 𝑧𝑖is the depth of the intersection
points. Unlike the distortion loss in Mip-NeRF360, where 𝑧𝑖is the
distance between sampled points and is not optimized, our approach
directly encourages the concentration of the splats by adjusting the
intersection depth 𝑧𝑖. Note that we implement this regularization
term efficiently with CUDA in a manner similar to [Sun et al. 2022b].
Normal Consistency: As our representation is based on 2D Gauss-
ian surface elements, we must ensure that all 2D splats are locally
aligned with the actual surfaces. In the context of volume rendering
where multiple semi-transparent surfels may exist along the ray,
we consider the actual surface at the median point of intersection,
where the accumulated opacity reaches 0.5. We then align the splats’
normal with the gradients of the depth maps as follows:
L𝑛=
∑︁
𝑖
𝜔𝑖(1 −n⊤
𝑖N)
(14)
where 𝑖indexes over intersected splats along the ray, 𝜔denotes the
blending weight of the intersection point, n𝑖represents the normal
of the splat that is oriented towards the camera, and N is the normal
estimated by the nearby depth point p. Specifically, N is computed
with finite differences as follows:
N(𝑥,𝑦) = ∇𝑥p × ∇𝑦p
|∇𝑥p × ∇𝑦p|
(15)
By aligning the splat normal with the estimated surface normal, we
ensure that 2D splats locally approximate the actual object surface.
Final Loss: Finally, we optimize our model from an initial sparse
point cloud using a set of posed images. We minimize the following
loss function:
L = L𝑐+ 𝛼L𝑑+ 𝛽L𝑛
(16)
where L𝑐is an RGB reconstruction loss combining L1 with the
D-SSIM term from [Kerbl et al. 2023], while L𝑑and L𝑛are regu-
larization terms. We set 𝛼= 1000 for bounded scenes, 𝛼= 100 for
unbounded scenes and 𝛽= 0.05 for all scenes.
6
EXPERIMENTS
We now present an extensive evaluation of our 2D Gaussian Splat-
ting reconstruction method, including appearance and geometry
comparison with previous state-of-the-art implicit and explicit ap-
proaches. We then analyze the contribution of the proposed compo-
nents.
6.1
Implementation
We implement our 2D Gaussian Splatting with custom CUDA ker-
nels, building upon the framework of 3DGS [Kerbl et al. 2023]. We
extend the renderer to output depth distortion maps, depth maps
and normal maps for regularizations. During training, we increase
the number of 2D Gaussian primitives following the adaptive con-
trol strategy in 3DGS. Since our method does not directly rely on
the gradient of the projected 2D center, we hence project the gra-
dient of 3D center p𝑘onto the screen space as an approximation.
Similarly, we employ a gradient threshold of 0.0002 and remove
splats with opacity lower than 0.05 every 3000 step. We conduct all
the experiments on a single GTX RTX3090 GPU.
Mesh Extraction: To extract meshes from reconstructed 2D splats,
we render depth maps of the training views using the median depth
value of the splats projected to the pixels and utilize truncated signed
distance fusion (TSDF) to fuse the reconstruction depth maps, using
Open3D [Zhou et al. 2018]. We set the voxel size to 0.004 and the
truncated threshold to 0.02 during TSDF fusion. We also extend the
original 3DGS to render depth and employ the same technique for
surface reconstruction for a fair comparison.
6.2
Comparison
Dataset: We evaluate the performance of our method on vari-
ous datasets, including DTU [Jensen et al. 2014], Tanks and Tem-
ples [Knapitsch et al. 2017], and Mip-NeRF360 [Barron et al. 2022a].
The DTU dataset comprises 15 scenes, each with 49 or 69 images of
resolution 1600 × 1200. We use Colmap [Schönberger and Frahm
2016] to generate a sparse point cloud for each scene and down-
sample the images into a resolution of 800 × 600 for efficiency. We
use the same training process for 3DGS [Kerbl et al. 2023] and
SuGar [Guédon and Lepetit 2023] for a fair comparison.
Geometry Reconstruction: In Table 1 and Table 3, we compare
our geometry reconstruction to SOTA implicit (i.e., NeRF [Milden-
hall et al. 2020], VolSDF [Yariv et al. 2021], and NeuS [Wang et al.
2021]), explicit (i.e., 3DGS [Kerbl et al. 2023] and concurrent work
SuGaR [Guédon and Lepetit 2023]) on Chamfer distance and train-
ing time using the DTU dataset. Our method outperforms all com-
pared methods in terms of Chamfer distance. Moreover, as shown
in Table 2, 2DGS achieves competitive results with SDF models
(i.e., NeuS [Wang et al. 2021] and Geo-Neus [Fu et al. 2022]) on the


6
•
Binbin Huang, Zehao Yu, Anpei Chen, Andreas Geiger, and Shenghua Gao
Ground truth
Ours (color)
Ours (normal)
3DGS
SuGaR
Ours
Fig. 4. Visual comparisons (test-set view) between our method, 3DGS, and SuGaR using scenes from an unbounded real-world dataset - kitchen, bicycle,
stump, and treehill. The first column displays the ground truth novel view, while the second and the third columns showcase our rendering results,
demonstrating high-fidelity novel view and accurate geometry. Columns four and five present surface reconstruction results from our method and 3DGS,
utilizing TSDF fusion with a depth range of 6 meters. Background regions (outside this range) are colored light gray. The sixth column displays results from
SuGaR. In contrast to both baselines, our method excels in capturing sharp edges and intricate geometry.
Table 1. Quantitative comparison on the DTU Dataset [Jensen et al. 2014]. Our 2DGS achieves the highest reconstruction accuracy among other methods and
provides 100× speed up compared to the SDF based baselines.
24
37
40
55
63
65
69
83
97
105
106
110
114
118
122
Mean
Time
implicit
NeRF [Mildenhall et al. 2021]
1.90
1.60
1.85
0.58
2.28
1.27
1.47
1.67
2.05
1.07
0.88
2.53
1.06
1.15
0.96
1.49
> 12h
VolSDF [Yariv et al. 2021]
1.14
1.26
0.81
0.49
1.25
0.70
0.72
1.29
1.18
0.70
0.66
1.08
0.42
0.61
0.55
0.86
>12h
NeuS [Wang et al. 2021]
1.00
1.37
0.93
0.43
1.10
0.65
0.57
1.48
1.09
0.83
0.52
1.20
0.35
0.49
0.54
0.84
>12h
explicit
3DGS [Kerbl et al. 2023]
2.14
1.53
2.08
1.68
3.49
2.21
1.43
2.07
2.22
1.75
1.79
2.55
1.53
1.52
1.50
1.96
11.2 m
SuGaR [Guédon and Lepetit 2023]
1.47
1.33
1.13
0.61
2.25
1.71
1.15
1.63
1.62
1.07
0.79
2.45
0.98
0.88
0.79
1.33
∼1h
2DGS-15k (Ours)
0.48
0.92
0.42
0.40
1.04
0.83
0.83
1.36
1.27
0.76
0.72
1.63
0.40
0.76
0.60
0.83
5.5 m
2DGS-30k (Ours)
0.48
0.91
0.39
0.39
1.01
0.83
0.81
1.36
1.27
0.76
0.70
1.40
0.40
0.76
0.52
0.80
18.8 m
Table 2. Quantitative results on the Tanks and Temples Dataset [Knapitsch
et al. 2017]. We report the F1 score and training time.
NeuS
Geo-Neus
Neurlangelo
SuGaR
3DGS
Ours
Barn
0.29
0.33
0.70
0.14
0.13
0.36
Caterpillar
0.29
0.26
0.36
0.16
0.08
0.23
Courthouse
0.17
0.12
0.28
0.08
0.09
0.13
Ignatius
0.83
0.72
0.89
0.33
0.04
0.44
Meetingroom
0.24
0.20
0.32
0.15
0.01
0.16
Truck
0.45
0.45
0.48
0.26
0.19
0.26
Mean
0.38
0.35
0.50
0.19
0.09
0.30
Time
>24h
>24h
>24h
>1h
14.3 m
34.2 m
TnT dataset, and significantly better reconstruction than explicit
reconstruction methods (i.e., 3DGS and SuGaR). Notably, our model
demonstrates exceptional efficiency, offering a reconstruction speed
that is approximately 100 times faster compared to implicit recon-
struction methods and more than 3 times faster than the concurrent
Table 3. Performance comparison between 2DGS (ours), 3DGS and SuGaR
on the DTU dataset [Jensen et al. 2014]. We report the averaged chamfer
distance, PSNR, reconstruction time, and model size.
CD ↓
PSNR ↑
Time ↓
MB (Storage) ↓
3DGS [Kerbl et al. 2023]
1.96
35.76
11.2 m
113
SuGaR [Guédon and Lepetit 2023]
1.33
34.57
∼1 h
1247
2DGS-15k (Ours)
0.83
33.42
5.5 m
52
2DGS-30k (Ours)
0.80
34.52
18.8 m
52
work SuGaR. Our approach can also achieve qualitatively better
reconstructions with more appearance and geometry details and
fewer outliers, as shown in Figure 5. We include the geometry recon-
struction results in supplementary Figure 10. Moreover, SDF-based
reconstruction methods require predefining the spherical size for
initialization, which plays a critical role in the success of SDF recon-
struction. Bu contrast, our method leverages radiance field based
geometry modeling and is less sensitive to initialization.


2D Gaussian Splatting for Geometrically Accurate Radiance Fields
•
7
Fig. 5. Qualitative comparison on the DTU benchmark [Jensen et al. 2014].
Our 2DGS produces detailed and noise-free surfaces.
Table 4. Quantitative results on Mip-NeRF 360 [Barron et al. 2022a] dataset.
All scores of the baseline methods are directly taken from their papers
whenever available. We report the performance of 3DGS, SuGaR and ours
using 30𝑘iterations.
Outdoor Scene
Indoor scene
PSNR ↑
SSIM ↑
LIPPS ↓
PSNR ↑
SSIM ↑
LIPPS ↓
NeRF
21.46
0.458
0.515
26.84
0.790
0.370
Deep Blending
21.54
0.524
0.364
26.40
0.844
0.261
Instant NGP
22.90
0.566
0.371
29.15
0.880
0.216
MERF
23.19
0.616
0.343
27.80
0.855
0.271
MipNeRF360
24.47
0.691
0.283
31.72
0.917
0.180
BakedSDF
22.47
0.585
0.349
27.06
0.836
0.258
Mobile-NeRF
21.95
0.470
0.470
-
-
-
3DGS
24.24
0.705
0.283
30.99
0.926
0.199
SuGaR
22.76
0.631
0.349
29.44
0.911
0.216
2DGS (Ours)
24.33
0.709
0.284
30.39
0.924
0.182
Appearance Reconstruction: Our method represents 3D scenes
as radiance fields, providing high-quality novel view synthesis. In
this section, we compare our novel view renderings using the Mip-
NeRF360 dataset against baseline approaches, as shown in Table 4
and Figure 4. Note that, since the ground truth geometry is not
available in the Mip-NeRF360 dataset and we hence focus on quan-
titative comparison. Remarkably, our method consistently achieves
competitive NVS results across state-of-the-art techniques while
providing geometrically accurate surface reconstruction.
6.3
Ablations
In this section, we isolate the design choices and measure their effect
on reconstruction quality, including regularization terms and mesh
extraction. We conduct experiments on the DTU dataset [Jensen et al.
2014] with 15𝑘iterations and report the reconstruction accuracy,
completeness and average reconstruction quality. The quantitative
effect of the choices is reported in Table 5.
Regularization: We first examine the effects of the proposed nor-
mal consistency and depth distortion regularization terms. Our
model (Table 5 E) provides the best performance when applying
both regularization terms. We observe that disabling the normal
consistency (Table 5 A) can lead to incorrect orientation, as shown
in Figure 6 A. Additionally, the absence of depth distortion (Table 5
B) results in a noisy surface, as shown in Figure 6 B.
Table 5. Quantitative studies for the regularization terms and mesh extrac-
tion methods on the DTU dataset.
Accuracy ↓
Completion ↓
Averagy ↓
A. w/o normal consistency
1.35
1.13
1.24
B. w/o depth distortion
0.89
0.87
0.88
C. w / expected depth
0.88
1.01
0.94
D. w / Poisson
1.25
0.89
1.07
E. Full Model
0.79
0.86
0.83
Input
(A) w/o. NC
(B) w/o. DD
Full Model
Fig. 6. Qualitative studies for the regularization effects. From left to right –
input image, surface normals without normal consistency, without depth
distortion, and our full model. Disabling the normal consistency loss leads
to noisy surface orientations; conversely, omitting depth distortion regular-
ization results in blurred surface normals. The complete model, employing
both regularizations, successfully captures sharp and flat features.
Mesh Extraction: We now analyze our choice for mesh extraction.
Our full model (Table 5 E) utilizes TSDF fusion for mesh extraction
with median depth. One alternative option is to use the expected
depth instead of the median depth. However, it yields worse recon-
structions as it is more sensitive to outliers, as shown in Table 5
C. Further, our approach surpasses screened Poisson surface recon-
struction (SPSR)(Table 5 D) [Kazhdan and Hoppe 2013] using 2D
Gaussians’ center and normal as inputs, due to SPSR’s inability to
incorporate the opacity and the size of 2D Gaussian primitives.
7
CONCLUSION
We presented 2D Gaussian splatting, a novel approach for geomet-
rically accurate radiance field reconstruction. We utilized 2D Gauss-
ian primitives for 3D scene representation, facilitating accurate and
view consistent geometry modeling and rendering. We proposed
two regularization techniques to further enhance the reconstructed
geometry. Extensive experiments on several challenging datasets
verify the effectiveness and efficiency of our method.
Limitations: While our method successfully delivers accurate ap-
pearance and geometry reconstruction for a wide range of objects
and scenes, we also discuss its limitations: First, we assume surfaces
with full opacity and extract meshes from multi-view depth maps.
This can pose challenges in accurately handling semi-transparent
surfaces, such as glass, due to their complex light transmission prop-
erties. Secondly, our current densification strategy favors texture-
rich over geometry-rich areas, occasionally leading to less accurate
representations of fine geometric structures. A more effective densi-
fication strategy could mitigate this issue. Finally, our regularization
often involves a trade-off between image quality and geometry, and
can potentially lead to oversmoothing in certain regions.


8
•
Binbin Huang, Zehao Yu, Anpei Chen, Andreas Geiger, and Shenghua Gao
Acknowledgement: BH and SG are supported by NSFC #62172279,
#61932020, Program of Shanghai Academic Research Leader. ZY, AC
and AG are supported by the ERC Starting Grant LEGO-3D (850533)
and DFG EXC number 2064/1 - project number 390727645.
REFERENCES
Kara-Ali Aliev, Artem Sevastopolsky, Maria Kolos, Dmitry Ulyanov, and Victor Lem-
pitsky. 2020. Neural point-based graphics. In Computer Vision–ECCV 2020: 16th
European Conference, Glasgow, UK, August 23–28, 2020, Proceedings, Part XXII 16.
Springer, 696–712.
Jonathan T. Barron, Ben Mildenhall, Matthew Tancik, Peter Hedman, Ricardo Martin-
Brualla, and Pratul P. Srinivasan. 2021. Mip-NeRF: A Multiscale Representation for
Anti-Aliasing Neural Radiance Fields. ICCV (2021).
Jonathan T Barron, Ben Mildenhall, Dor Verbin, Pratul P Srinivasan, and Peter Hedman.
2022a. Mip-nerf 360: Unbounded anti-aliased neural radiance fields. In Proceedings
of the IEEE/CVF Conference on Computer Vision and Pattern Recognition. 5470–5479.
Jonathan T. Barron, Ben Mildenhall, Dor Verbin, Pratul P. Srinivasan, and Peter Hedman.
2022b. Mip-NeRF 360: Unbounded Anti-Aliased Neural Radiance Fields. CVPR (2022).
Jonathan T. Barron, Ben Mildenhall, Dor Verbin, Pratul P. Srinivasan, and Peter Hedman.
2023. Zip-NeRF: Anti-Aliased Grid-Based Neural Radiance Fields. ICCV (2023).
Mario Botsch, Alexander Hornung, Matthias Zwicker, and Leif Kobbelt. 2005. High-
quality surface splatting on today’s GPUs. In Proceedings Eurographics/IEEE VGTC
Symposium Point-Based Graphics, 2005. IEEE, 17–141.
Anpei Chen, Zexiang Xu, Andreas Geiger, Jingyi Yu, and Hao Su. 2022. TensoRF:
Tensorial Radiance Fields. In European Conference on Computer Vision (ECCV).
Hanlin Chen, Chen Li, and Gim Hee Lee. 2023b. NeuSG: Neural Implicit Surface Re-
construction with 3D Gaussian Splatting Guidance. arXiv preprint arXiv:2312.00846
(2023).
Zhiqin Chen, Thomas Funkhouser, Peter Hedman, and Andrea Tagliasacchi. 2023a.
Mobilenerf: Exploiting the polygon rasterization pipeline for efficient neural field
rendering on mobile architectures. In Proceedings of the IEEE/CVF Conference on
Computer Vision and Pattern Recognition. 16569–16578.
Zhang Chen, Zhong Li, Liangchen Song, Lele Chen, Jingyi Yu, Junsong Yuan, and Yi
Xu. 2023c. NeuRBF: A Neural Fields Representation with Adaptive Radial Basis
Functions. In Proceedings of the IEEE/CVF International Conference on Computer
Vision. 4182–4194.
Sara Fridovich-Keil, Alex Yu, Matthew Tancik, Qinhong Chen, Benjamin Recht, and
Angjoo Kanazawa. 2022. Plenoxels: Radiance Fields without Neural Networks. In
CVPR.
Qiancheng Fu, Qingshan Xu, Yew-Soon Ong, and Wenbing Tao. 2022. Geo-Neus:
Geometry-Consistent Neural Implicit Surfaces Learning for Multi-view Reconstruc-
tion. Advances in Neural Information Processing Systems (NeurIPS) (2022).
Jian Gao, Chun Gu, Youtian Lin, Hao Zhu, Xun Cao, Li Zhang, and Yao Yao. 2023. Re-
lightable 3D Gaussian: Real-time Point Cloud Relighting with BRDF Decomposition
and Ray Tracing. arXiv:2311.16043 (2023).
Antoine Guédon and Vincent Lepetit. 2023. SuGaR: Surface-Aligned Gaussian Splatting
for Efficient 3D Mesh Reconstruction and High-Quality Mesh Rendering. arXiv
preprint arXiv:2311.12775 (2023).
Peter Hedman, Pratul P Srinivasan, Ben Mildenhall, Jonathan T Barron, and Paul De-
bevec. 2021. Baking neural radiance fields for real-time view synthesis. In Proceedings
of the IEEE/CVF International Conference on Computer Vision. 5875–5884.
Wenbo Hu, Yuling Wang, Lin Ma, Bangbang Yang, Lin Gao, Xiao Liu, and Yuewen
Ma. 2023. Tri-MipRF: Tri-Mip Representation for Efficient Anti-Aliasing Neural
Radiance Fields. In ICCV.
Eldar Insafutdinov and Alexey Dosovitskiy. 2018. Unsupervised learning of shape and
pose with differentiable point clouds. Advances in neural information processing
systems 31 (2018).
Rasmus Jensen, Anders Dahl, George Vogiatzis, Engin Tola, and Henrik Aanæs. 2014.
Large scale multi-view stereopsis evaluation. In Proceedings of the IEEE conference
on computer vision and pattern recognition. 406–413.
Yingwenqi Jiang, Jiadong Tu, Yuan Liu, Xifeng Gao, Xiaoxiao Long, Wenping Wang, and
Yuexin Ma. 2023. GaussianShader: 3D Gaussian Splatting with Shading Functions
for Reflective Surfaces. arXiv preprint arXiv:2311.17977 (2023).
Michael Kazhdan and Hugues Hoppe. 2013. Screened poisson surface reconstruction.
ACM Transactions on Graphics (ToG) 32, 3 (2013), 1–13.
Bernhard Kerbl, Georgios Kopanas, Thomas Leimkühler, and George Drettakis. 2023.
3D Gaussian Splatting for Real-Time Radiance Field Rendering. ACM Transactions on
Graphics 42, 4 (July 2023). https://repo-sam.inria.fr/fungraph/3d-gaussian-splatting/
Leonid Keselman and Martial Hebert. 2022. Approximate differentiable rendering with
algebraic surfaces. In European Conference on Computer Vision. Springer, 596–614.
Leonid Keselman and Martial Hebert. 2023. Flexible techniques for differentiable
rendering with 3d gaussians. arXiv preprint arXiv:2308.14737 (2023).
Arno Knapitsch, Jaesik Park, Qian-Yi Zhou, and Vladlen Koltun. 2017. Tanks and
Temples: Benchmarking Large-Scale Scene Reconstruction. ACM Transactions on
Graphics 36, 4 (2017).
Georgios Kopanas, Julien Philip, Thomas Leimkühler, and George Drettakis. 2021. Point-
Based Neural Rendering with Per-View Optimization. In Computer Graphics Forum,
Vol. 40. Wiley Online Library, 29–43.
Christoph Lassner and Michael Zollhofer. 2021. Pulsar: Efficient sphere-based neural
rendering. In Proceedings of the IEEE/CVF Conference on Computer Vision and Pattern
Recognition. 1440–1449.
Zhaoshuo Li, Thomas Müller, Alex Evans, Russell H Taylor, Mathias Unberath, Ming-
Yu Liu, and Chen-Hsuan Lin. 2023. Neuralangelo: High-Fidelity Neural Surface
Reconstruction. In IEEE Conference on Computer Vision and Pattern Recognition
(CVPR).
Zhihao Liang, Qi Zhang, Ying Feng, Ying Shan, and Kui Jia. 2023. GS-IR: 3D Gaussian
Splatting for Inverse Rendering. arXiv preprint arXiv:2311.16473 (2023).
Lingjie Liu, Jiatao Gu, Kyaw Zaw Lin, Tat-Seng Chua, and Christian Theobalt. 2020.
Neural Sparse Voxel Fields. NeurIPS (2020).
Jonathon Luiten, Georgios Kopanas, Bastian Leibe, and Deva Ramanan. 2024. Dynamic
3D Gaussians: Tracking by Persistent Dynamic View Synthesis. In 3DV.
Lars Mescheder, Michael Oechsle, Michael Niemeyer, Sebastian Nowozin, and Andreas
Geiger. 2019. Occupancy Networks: Learning 3D Reconstruction in Function Space.
In Conference on Computer Vision and Pattern Recognition (CVPR).
Ben Mildenhall, Pratul P. Srinivasan, Matthew Tancik, Jonathan T. Barron, Ravi Ra-
mamoorthi, and Ren Ng. 2020. NeRF: Representing Scenes as Neural Radiance Fields
for View Synthesis. In ECCV.
Ben Mildenhall, Pratul P Srinivasan, Matthew Tancik, Jonathan T Barron, Ravi Ra-
mamoorthi, and Ren Ng. 2021. Nerf: Representing scenes as neural radiance fields
for view synthesis. Commun. ACM 65, 1 (2021), 99–106.
Thomas Müller, Alex Evans, Christoph Schied, and Alexander Keller. 2022. Instant
Neural Graphics Primitives with a Multiresolution Hash Encoding. ACM Trans.
Graph. 41, 4, Article 102 (July 2022), 15 pages.
Michael Niemeyer, Lars Mescheder, Michael Oechsle, and Andreas Geiger. 2020. Differ-
entiable Volumetric Rendering: Learning Implicit 3D Representations without 3D
Supervision. In Conference on Computer Vision and Pattern Recognition (CVPR).
Michael Oechsle, Songyou Peng, and Andreas Geiger. 2021. UNISURF: Unifying Neural
Implicit Surfaces and Radiance Fields for Multi-View Reconstruction. In International
Conference on Computer Vision (ICCV).
Jeong Joon Park, Peter Florence, Julian Straub, Richard Newcombe, and Steven Love-
grove. 2019. DeepSDF: Learning Continuous Signed Distance Functions for Shape
Representation. In The IEEE Conference on Computer Vision and Pattern Recognition
(CVPR).
Hanspeter Pfister, Matthias Zwicker, Jeroen Van Baar, and Markus Gross. 2000. Surfels:
Surface elements as rendering primitives. In Proceedings of the 27th annual conference
on Computer graphics and interactive techniques. 335–342.
Shenhan Qian, Tobias Kirschstein, Liam Schoneveld, Davide Davoli, Simon Giebenhain,
and Matthias Nießner. 2023. GaussianAvatars: Photorealistic Head Avatars with
Rigged 3D Gaussians. arXiv preprint arXiv:2312.02069 (2023).
Christian Reiser, Songyou Peng, Yiyi Liao, and Andreas Geiger. 2021. KiloNeRF: Speed-
ing up Neural Radiance Fields with Thousands of Tiny MLPs. In International
Conference on Computer Vision (ICCV).
Christian Reiser, Rick Szeliski, Dor Verbin, Pratul Srinivasan, Ben Mildenhall, Andreas
Geiger, Jon Barron, and Peter Hedman. 2023. Merf: Memory-efficient radiance fields
for real-time view synthesis in unbounded scenes. ACM Transactions on Graphics
(TOG) 42, 4 (2023), 1–12.
Darius Rückert, Linus Franke, and Marc Stamminger. 2022. Adop: Approximate dif-
ferentiable one-pixel point rendering. ACM Transactions on Graphics (ToG) 41, 4
(2022), 1–14.
Johannes Lutz Schönberger and Jan-Michael Frahm. 2016. Structure-from-Motion
Revisited. In Conference on Computer Vision and Pattern Recognition (CVPR).
Johannes Lutz Schönberger, Enliang Zheng, Marc Pollefeys, and Jan-Michael Frahm.
2016. Pixelwise View Selection for Unstructured Multi-View Stereo. In European
Conference on Computer Vision (ECCV).
Thomas Schöps, Torsten Sattler, and Marc Pollefeys. 2019. Surfelmeshing: Online
surfel-based mesh reconstruction. IEEE transactions on pattern analysis and machine
intelligence 42, 10 (2019), 2494–2507.
Yahao Shi, Yanmin Wu, Chenming Wu, Xing Liu, Chen Zhao, Haocheng Feng, Jingtuo
Liu, Liangjun Zhang, Jian Zhang, Bin Zhou, Errui Ding, and Jingdong Wang. 2023.
GIR: 3D Gaussian Inverse Rendering for Relightable Scene Factorization. Arxiv
(2023). arXiv:2312.05133
Christian Sigg, Tim Weyrich, Mario Botsch, and Markus H Gross. 2006. GPU-based
ray-casting of quadratic surfaces.. In PBG@ SIGGRAPH. 59–65.
Cheng Sun, Min Sun, and Hwann-Tzong Chen. 2022a. Direct Voxel Grid Optimization:
Super-fast Convergence for Radiance Fields Reconstruction. In CVPR.
Cheng Sun, Min Sun, and Hwann-Tzong Chen. 2022b. Improved Direct Voxel Grid
Optimization for Radiance Fields Reconstruction. arxiv cs.GR 2206.05085 (2022).
John Vince. 2008. Geometric algebra for computer graphics. Springer Science & Business
Media.


2D Gaussian Splatting for Geometrically Accurate Radiance Fields
•
9
Peng Wang, Lingjie Liu, Yuan Liu, Christian Theobalt, Taku Komura, and Wenping
Wang. 2021. NeuS: Learning Neural Implicit Surfaces by Volume Rendering for
Multi-view Reconstruction. Advances in Neural Information Processing Systems 34
(2021), 27171–27183.
Yiming Wang, Qin Han, Marc Habermann, Kostas Daniilidis, Christian Theobalt, and
Lingjie Liu. 2023. NeuS2: Fast Learning of Neural Implicit Surfaces for Multi-view
Reconstruction. In Proceedings of the IEEE/CVF International Conference on Computer
Vision (ICCV).
Tim Weyrich, Simon Heinzle, Timo Aila, Daniel B Fasnacht, Stephan Oetiker, Mario
Botsch, Cyril Flaig, Simon Mall, Kaspar Rohrer, Norbert Felber, et al. 2007. A
hardware architecture for surface splatting. ACM Transactions on Graphics (TOG)
26, 3 (2007), 90–es.
Thomas Whelan, Renato F Salas-Moreno, Ben Glocker, Andrew J Davison, and Stefan
Leutenegger. 2016. ElasticFusion: Real-time dense SLAM and light source estimation.
The International Journal of Robotics Research 35, 14 (2016), 1697–1716.
Olivia Wiles, Georgia Gkioxari, Richard Szeliski, and Justin Johnson. 2020. SynSin:
End-to-end View Synthesis from a Single Image. In Proceedings of the IEEE/CVF
Conference on Computer Vision and Pattern Recognition (CVPR).
Tianyi Xie, Zeshun Zong, Yuxing Qiu, Xuan Li, Yutao Feng, Yin Yang, and Chenfanfu
Jiang. 2023. PhysGaussian: Physics-Integrated 3D Gaussians for Generative Dynam-
ics. arXiv preprint arXiv:2311.12198 (2023).
Yunzhi Yan, Haotong Lin, Chenxu Zhou, Weijie Wang, Haiyang Sun, Kun Zhan, Xi-
anpeng Lang, Xiaowei Zhou, and Sida Peng. 2023. Street Gaussians for Modeling
Dynamic Urban Scenes. (2023).
Yao Yao, Zixin Luo, Shiwei Li, Tian Fang, and Long Quan. 2018. MVSNet: Depth
Inference for Unstructured Multi-view Stereo. European Conference on Computer
Vision (ECCV) (2018).
Lior Yariv, Jiatao Gu, Yoni Kasten, and Yaron Lipman. 2021. Volume rendering of neural
implicit surfaces. Advances in Neural Information Processing Systems 34 (2021),
4805–4815.
Lior Yariv, Peter Hedman, Christian Reiser, Dor Verbin, Pratul P. Srinivasan, Richard
Szeliski, Jonathan T. Barron, and Ben Mildenhall. 2023. BakedSDF: Meshing Neural
SDFs for Real-Time View Synthesis. arXiv (2023).
Lior Yariv, Yoni Kasten, Dror Moran, Meirav Galun, Matan Atzmon, Basri Ronen, and
Yaron Lipman. 2020. Multiview Neural Surface Reconstruction by Disentangling
Geometry and Appearance. Advances in Neural Information Processing Systems 33
(2020).
Wang Yifan, Felice Serena, Shihao Wu, Cengiz Öztireli, and Olga Sorkine-Hornung.
2019. Differentiable surface splatting for point-based geometry processing. ACM
Transactions on Graphics (TOG) 38, 6 (2019), 1–14.
Alex Yu, Ruilong Li, Matthew Tancik, Hao Li, Ren Ng, and Angjoo Kanazawa. 2021.
PlenOctrees for Real-time Rendering of Neural Radiance Fields. In ICCV.
Zehao Yu, Anpei Chen, Bozidar Antic, Songyou Peng, Apratim Bhattacharyya, Michael
Niemeyer, Siyu Tang, Torsten Sattler, and Andreas Geiger. 2022a. SDFStudio: A Uni-
fied Framework for Surface Reconstruction. https://github.com/autonomousvision/
sdfstudio
Zehao Yu, Anpei Chen, Binbin Huang, Torsten Sattler, and Andreas Geiger. 2024. Mip-
Splatting: Alias-free 3D Gaussian Splatting. Conference on Computer Vision and
Pattern Recognition (CVPR) (2024).
Zehao Yu and Shenghua Gao. 2020. Fast-MVSNet: Sparse-to-Dense Multi-View Stereo
With Learned Propagation and Gauss-Newton Refinement. In Conference on Com-
puter Vision and Pattern Recognition (CVPR).
Zehao Yu, Songyou Peng, Michael Niemeyer, Torsten Sattler, and Andreas Geiger.
2022b. MonoSDF: Exploring Monocular Geometric Cues for Neural Implicit Surface
Reconstruction. Advances in Neural Information Processing Systems (NeurIPS) (2022).
Kai Zhang, Gernot Riegler, Noah Snavely, and Vladlen Koltun. 2020. NeRF++: Analyzing
and Improving Neural Radiance Fields. arXiv:2010.07492 (2020).
Qian-Yi Zhou, Jaesik Park, and Vladlen Koltun. 2018. Open3D: A Modern Library for
3D Data Processing. arXiv:1801.09847 (2018).
Wojciech Zielonka, Timur Bagautdinov, Shunsuke Saito, Michael Zollhöfer, Jus-
tus Thies, and Javier Romero. 2023.
Drivable 3D Gaussian Avatars.
(2023).
arXiv:2311.08581 [cs.CV]
Matthias Zwicker, Hanspeter Pfister, Jeroen Van Baar, and Markus Gross. 2001a. EWA
volume splatting. In Proceedings Visualization, 2001. VIS’01. IEEE, 29–538.
Matthias Zwicker, Hanspeter Pfister, Jeroen Van Baar, and Markus Gross. 2001b. Surface
splatting. In Proceedings of the 28th annual conference on Computer graphics and
interactive techniques. 371–378.
Matthias Zwicker, Jussi Rasanen, Mario Botsch, Carsten Dachsbacher, and Mark Pauly.
2004. Perspective accurate splatting. In Proceedings-Graphics Interface. 247–254.
A
DETAILS OF DEPTH DISTORTION
While Barron et al. [Barron et al. 2022b] calculates the distortion
loss with samples on the ray, we operate Gaussian primitives, where
the intersected depth may not be ordered. To this end, we adopt
Color
Depth
Ground truth
Ours 
3DGS
Fig. 7. Affine-approximation adopted in [Zwicker et al. 2001b][Kerbl et al.
2023] causes perspective distortion and inaccurate depth.
an L2 loss and transform the intersected depth 𝑧to NDC space to
down-weight distant Gaussian primitives, 𝑚= NDC(𝑧), with near
and far plane empirically set to 0.2 and 1000. We implemented our
depth distortion loss based on [Sun et al. 2022b], also powered by
tile-based rendering. Here we show that the nested algorithm can
be implemented in a single forward pass:
L =
𝑁−1
∑︁
𝑖=0
𝑖−1
∑︁
𝑗=0
𝜔𝑖𝜔𝑗(𝑚𝑖−𝑚𝑗)2
=
𝑁−1
∑︁
𝑖=0
𝜔𝑖
 
𝑚2
𝑖
𝑖−1
∑︁
𝑗=0
𝜔𝑗+
𝑖−1
∑︁
𝑗=0
𝜔𝑗𝑚2
𝑗−2𝑚𝑖
𝑖−1
∑︁
𝑗=0
𝜔𝑗𝑚𝑗
!
=
𝑁−1
∑︁
𝑖=0
𝜔𝑖

𝑚2
𝑖𝐴𝑖−1 + 𝐷2
𝑖−1 −2𝑚𝑖𝐷𝑖−1

,
(17)
where 𝐴𝑖= Í𝑖
𝑗=0 𝜔𝑗, 𝐷𝑖= Í𝑖
𝑗=0 𝜔𝑗𝑚𝑗and 𝐷2
𝑖= Í𝑖
𝑗=0 𝜔𝑗𝑚2
𝑗.
Specifically, we let 𝑒𝑖=

𝑚2
𝑖𝐴𝑖−1 + 𝐷2
𝑖−1 −2𝑚𝑖𝐷𝑖−1

so that the
distortion loss can be “rendered” as L𝑖= Í𝑖
𝑗=0 𝜔𝑗𝑒𝑗. Here, L𝑖mea-
sures the depth distortion up to the 𝑖-th Gaussian. During marching
Gaussian front-to-back, we simultaneously accumulate 𝐴𝑖, 𝐷𝑖and
𝐷2
𝑖, preparing for the next distortion computation L𝑖+1. Similarly,
the gradient of the depth distortion can be back-propagated to the
primitives back-to-front. Different from implicit methods where
𝑚are the pre-defined sampled depth and non-differentiable, we
additionally back-propagate the gradient through the intersection
𝑚, encouraging the Gaussians to move tightly together directly.
B
DEPTH CALCULATIONS
Mean depth:There are two optional depth computations used for
our meshing process. The mean (expected) depth is calculated by
weighting the intersected depth:
𝑧mean =
∑︁
𝑖
𝜔𝑖𝑧𝑖/(
∑︁
𝑖
𝜔𝑖+ 𝜖)
(18)
where 𝜔𝑖= 𝑇𝑖𝛼𝑖ˆ
G𝑖(u(x) is the weight contribution of the 𝑖-th
Gaussian and 𝑇𝑖= Î𝑖−1
𝑗=1(1 −𝛼𝑗ˆ
G𝑗(u(x))) measures its visibility.
It is important to normalize the depth with the accumulated alpha
𝐴= Í
𝑖𝜔𝑖to ensure that a 2D Gaussian can be rendered as a planar
2D disk in the depth visualization.


10
•
Binbin Huang, Zehao Yu, Anpei Chen, Andreas Geiger, and Shenghua Gao
(a) Ground-truth
(b) MipNeRF360 [Barron et al. 2022b], SSIM=0.813
(c) 3DGS, normals from depth points
(d) 3DGS [Kerbl et al. 2023], SSIM=0.834
(e) Our model (2DGS), normals from depth points
(f) Our model (2DGS), SSIM=0.845
Fig. 8. We visualize the depth maps generated by MipNeRF360 [Barron et al. 2022b], 3DGS [Kerbl et al. 2023], and our method. The depth maps for 3DGS (d)
and 2DGS (f) are rendered using Eq. 18 and visualized following MipNeRF360. To highlight the surface smoothness, we further visualize the normal estimated
from depth points using Eq. 15 for both 3DGS (c) and ours (e). While MipNeRF360 is capable of producing plausibly smooth depth maps, its sampling process
may result in the loss of detailed structures. Both 3DGS and 2DGS excel at modeling thin structures; however, as illustrated in (c) and (e), the depth map of
3DGS exhibits significant noise. In contrast, our approach generates sampled depth points with normals consistent with the rendered normal map (refer to
Figure 1b), thereby enhancing depth fusion during the meshing process.
Table 6. PSNR↑, SSIM↑, LIPPS↓scores for MipNeRF360 dataset.
bicycle
flowers
garden
stump
treehill
room
counter
kitchen
bonsai
mean
3DGS
24.71
21.09
26.63
26.45
22.33
31.50
29.07
31.13
32.26
27.24
SuGaR
23.12
19.25
25.43
24.69
21.33
30.12
27.57
29.48
30.59
25.73
Ours
24.82
20.99
26.91
26.41
22.52
30.86
28.45
30.62
31.64
27.03
3DGS
0.729
0.571
0.834
0.762
0.627
0.922
0.913
0.926
0.943
0.803
SuGaR
0.639
0.486
0.776
0.686
0.566
0.910
0.892
0.908
0.932
0.755
Ours
0.731
0.573
0.845
0.764
0.630
0.918
0.908
0.927
0.940
0.804
3DGS
0.265
0.377
0.147
0.266
0.362
0.231
0.212
0.138
0.214
0.246
SuGaR
0.344
0.416
0.220
0.335
0.429
0.245
0.232
0.164
0.221
0.290
Ours
0.271
0.378
0.138
0.263
0.369
0.214
0.197
0.125
0.194
0.239
Table 7. PSNR scores for Synthetic NeRF dataset [Mildenhall et al. 2021].
Mic
Chair
Ship
Materials
Lego
Drums
Ficus
Hotdog
Avg.
Plenoxels
33.26
33.98
29.62
29.14
34.10
25.35
31.83
36.81
31.76
INGP-Base
36.22
35.00
31.10
29.78
36.39
26.02
33.51
37.40
33.18
Mip-NeRF
36.51
35.14
30.41
30.71
35.70
25.48
33.29
37.48
33.09
Point-NeRF
35.95
35.40
30.97
29.61
35.04
26.06
36.13
37.30
33.30
3DGS
35.36
35.83
30.80
30.00
35.78
26.15
34.87
37.72
33.32
2DGS (Ours)
35.09
35.05
30.60
29.74
35.10
26.05
35.57
37.36
33.07
Median depth:We compute the median depth as the largest “visible”
depth, considering 𝑇𝑖= 0.5 as the pivot for surface and free space:
𝑧median = max{𝑧𝑖|𝑇𝑖> 0.5}.
(19)
We find our median depth computation is more robust to [Luiten
et al. 2024]. When a ray’s accumulated alpha does not reach 0.5,
while Luiten et al. sets a default value of 15, our computation selects
the last Gaussian, which is more accurate and suitable for training.
C
ADDITIONAL RESULTS
Our 2D Gaussian Splatting method achieves comparable perfor-
mance even without the need for regularizations, as Table 7 shows.
Additionally, we have provided a breakdown of various per-scene
metrics for the MipNeRF360 dataset [Barron et al. 2022b] in Tables 6.
Figure 8 presents a comparison of our rendered depth maps with
those from 3DGS and MipNeRF360.


2D Gaussian Splatting for Geometrically Accurate Radiance Fields
•
11
scan24
scan37
scan40
scan55
scan63
scan65
scan69
scan83
scan97
scan105
scan106
scan110
scan114
scan118
scan122
scan24
scan37
scan40
scan55
scan63
scan65
scan69
scan83
scan97
scan105
scan106
scan110
scan114
scan118
scan122
2DGS
3DGS
Fig. 9. Comparison of surface reconstruction using our 2DGS and 3DGS [Kerbl et al. 2023]. Meshes are extracted by applying TSDF to the depth maps.


12
•
Binbin Huang, Zehao Yu, Anpei Chen, Andreas Geiger, and Shenghua Gao
Barn
Truck
Caterpillar
MeetingRoom
Ignatius
Fig. 10. Qualitative studies for the Tanks and Temples dataset [Knapitsch et al. 2017].
Fig. 11. Appearance rendering results from reconstructed 2D Gaussian disks, including DTU, TnT, and Mip-NeRF360 datasets.
(A) Semi-transparent
(B) High light
Fig. 12. Illustration of limitations: Our 2DGS struggles with the accurate reconstruction of semi-transparent surfaces, for example, the glass shown in example
(A). Moreover, our method tends to create holes in areas with high light intensity, as shown in (B).
</documents>

Both 3D Gaussian Splatting (3DGS) and 2D Gaussian Splatting (2DGS) seek to project Gaussians onto screen space for novel view synthesis, but their methods of handling surface projection and depth consistency differ. The 3D Gaussian splat is governed by:


G(p) = \exp\left(-\frac{1}{2}(p - p_k)^\top \Sigma^{-1} (p - p_k)\right)


where \Sigma represents the covariance matrix that controls the orientation and scaling of the Gaussian in 3D space. In contrast, 2D Gaussian Splatting collapses the volume into 2D elliptical disks embedded in 3D space to improve multi-view consistency.

Given the key differences between 3DGS and 2DGS, which of the following best explains how 2D Gaussian Splatting achieves superior surface projection accuracy, and what is the main mathematical reasoning behind this improvement?

A. 2D Gaussian Splatting improves projection accuracy by flattening the 3D Gaussian volume into a 2D disk, which allows for multi-scale affine transformations to align the splats with surface geometry. While 3D Gaussian Splatting relies on covariance matrix factorization to adjust Gaussian scaling, 2DGS avoids the need for this factorization by using homogeneous transformations that directly operate on 2D tangent planes. This enables consistent projections across views, as the surface normals are inherently preserved by aligning the splat’s principal directions to the surface.
B. 2D Gaussian Splatting resolves depth inconsistencies by applying a perspective-accurate ray-splat intersection technique, which uses a depth-weighted variance reduction process to ensure Gaussian splats align more tightly with the object’s surface. Unlike 3D Gaussian Splatting, which uses volumetric Gaussian splatting with affine projection matrices, 2DGS eliminates the distortions caused by depth gradients through the use of conic surface projections. This ensures that the splats are concentrated along the surface with minimal distortion, improving surface reconstruction accuracy across multiple views.
C. 2D Gaussian Splatting surpasses 3D Gaussian Splatting by eliminating the need for depth gradient-based normal inference. In 3DGS, normals are derived from depth gradients, which vary depending on the intersection of the Gaussian with the camera ray. 2DGS introduces principal curvature alignment, where the splat’s normal is computed directly from the Gaussian’s tangent vectors, ensuring consistent alignment with the surface normals across views. This prevents the angular discrepancies caused by varying projection planes in 3DGS, which leads to inaccurate surface reconstructions.
D. 2D Gaussian Splatting handles multi-view inconsistencies by employing a depth distortion loss that compresses the variance of the splats along the ray-splat intersection points, ensuring more accurate alignment with surface geometry. 3D Gaussian Splatting relies on a volumetric projection technique, where the Gaussian’s contribution is spread over multiple depths, leading to inconsistent surface reconstruction. By utilizing a projective splat accumulation process, 2DGS ensures that the projected splats remain aligned across views, avoiding the distortions caused by the varying depth intersections in 3DGS.

Answer with the letter of the correct option. Think it through, then end your reply with exactly: The answer is (X).
```

---

## Q10 · LiveCodeBench abc390_d Stone XOR (atcoder medium 2025-01-25)

- 来源：**LiveCodeBench**（2025-01-25）
- 轴：近期编程　类型：`lcb_ref`
- 官方答案键：`3 public tests`
- 判分键（重排后）：`(official tests)`
- `max_tokens`：**40960**
- 说明 / 来源记录：官方公开用例 3 个（= 题面样例，testtype=stdin）+ 参考实现生成用例 10 个；参考实现（集合划分穷举）已对全部官方用例逐一验证一致后才用于生成。

### Prompt

```text
Solve the following competitive programming problem.

There are N bags, labeled bag 1, bag 2, \ldots, bag N.
Bag i (1 \leq i \leq N) contains A_i stones.
Takahashi can perform the following operation any number of times, possibly zero:

Choose two bags A and B, and move all stones from bag A into bag B.

Find the number of different possible values for the following after repeating the operation.

- B_1 \oplus B_2 \oplus \cdots \oplus B_N, where B_i is the final number of stones in bag i.
Here, \oplus denotes bitwise XOR.


About bitwise XOR
For non-negative integers a and b, the bitwise XOR a \oplus b is defined as follows:


In the binary representation of a \oplus b, the digit in the 2^k place (k \ge 0) is 1 if and only if exactly one of the digits in the 2^k place of a and b is 1; otherwise, it is 0.


For example, 3 \oplus 5 = 6 (in binary, 011 \oplus 101 = 110).
In general, for k non-negative integers x_1, x_2, \ldots, x_k, their bitwise XOR x_1 \oplus x_2 \oplus \cdots \oplus x_k is defined as (\cdots((x_1 \oplus x_2) \oplus x_3) \oplus \cdots) \oplus x_k, which does not depend on the order of x_1, x_2, \ldots, x_k.

It can be proved that under the constraints of this problem, the number of possible values is finite.

Input

The input is given from Standard Input in the following format:
N
A_1 A_2 \ldots A_N

Output

Print the number of different possible values for B_1 \oplus B_2 \oplus \cdots \oplus B_N after repeating the operation.

Constraints


- 2 \leq N \leq 12
- 1 \leq A_i \leq 10^{17}
- All input values are integers.

Sample Input 1

3
2 5 7

Sample Output 1

3

For example, if Takahashi chooses bags 1 and 3 for the operation, then the numbers of stones in bags 1, 2, 3 become 0, 5, 9.
If he stops at this point, the XOR is 0 \oplus 5 \oplus 9 = 12.
The other possible XOR values after repeating the operation are 0 and 14.
Therefore, the possible values are 0, 12, 14; there are three values, so the output is 3.

Sample Input 2

2
100000000000000000 100000000000000000

Sample Output 2

2

Sample Input 3

6
71 74 45 34 31 60

Sample Output 3

84

Write a complete Python 3 program that reads from standard input and writes to standard output. Output the program in a single ```python code block.
```

### 官方 / 参考用例（`lcb_ref` 判分用）

1. `official-public` — stdin `'3\n2 5 7'` → stdout `'3'`
2. `official-public` — stdin `'2\n100000000000000000 100000000000000000'` → stdout `'2'`
3. `official-public` — stdin `'6\n71 74 45 34 31 60'` → stdout `'84'`
4. `reference(random small)` — stdin `'7\n17 8 21 7 20 24 4'` → stdout `'35'`
5. `reference(random small)` — stdin `'5\n1 16 30 15 13'` → stdout `'11'`
6. `reference(random small)` — stdin `'6\n4 20 28 36 37 17'` → stdout `'30'`
7. `reference(random small)` — stdin `'7\n5 28 2 12 17 6 5'` → stdout `'36'`
8. `reference(random large)` — stdin `'10\n53567606045886272 11169849041099303 99240714273804478 21986304061026203 22196718853389476 38236842061269252 49693732424434032 62522385984106630 75495963541850409 53048867173703477'` → stdout `'115975'`
9. `reference(random large)` — stdin `'11\n25057795245126836 1301082981820948 61718970520148144 48315073242120398 27922589263514523 8927946567806921 73773435010835560 41669113815500413 55079609461171490 55383950096413355 98839939417610601'` → stdout `'678565'`
10. `reference(random large)` — stdin `'10\n6942437536150804 14450346432105371 24200359223625293 31931320427463408 89347907875832721 67020532011528944 70175404801214177 25393583643412833 45639244152077322 16055954360356234'` → stdout `'115975'`
11. `reference(random large)` — stdin `'12\n48036688953653107 4712912535119647 85120850824325058 72022989467048837 19329695544039998 27290821372823190 92346442862078148 69907858997027135 22893642402319612 1375095257492017 57779206388430157 48968816164100840'` → stdout `'4213595'`
12. `reference(boundary)` — stdin `'2\n1 1'` → stdout `'2'`
13. `reference(boundary)` — stdin `'12\n100000000000000000 100000000000000000 100000000000000000 100000000000000000 100000000000000000 100000000000000000 100000000000000000 100000000000000000 100000000000000000 100000000000000000 100000000000000000 100000000000000000'` → stdout `'39'`

---
