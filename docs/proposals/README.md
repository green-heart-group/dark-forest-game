# 提议

团队成员提出的新想法、改动方案、试玩意见，都放这里。每次一个新文件。

## 怎么写

- 文件名用简短的英文主题，不带日期，例如 `warp-drive.md`。试玩意见用 `feedback-` 开头，
  例如 `feedback-star-map.md`。哪天提的记在下面的列表里；想看每次改动的时间，用
  `git log --follow -- docs/proposals/文件名`。
- 草图和图片放在 [images/](images/)，文件名和提议对应，例如 `tech-tree.png`。
- 写好以后 commit，并在下面的列表最后加一行：日期、文件、状态、一句话说明。不会加也没关系，整理时补上。

有两种写法：

### 意见（随手写）

试玩意见、小改动、发现的 bug。开头写一行 `状态：待整理`，下面一条一行，怎么写都行。
想回答 [要确定的问题](../open-questions.md) 里的某一条，可以直接在那边填「决定」，也可以写在这里并带上编号，例如「T18：选 B」。

### 提议（大的改动）

要改一大块规则时用。开头写清楚谁提的、状态、想解决什么问题；有需要大家选的地方，列出选项和推荐，
问题按组编号（例如 G1、T1）。还有没回答的问题时，在 [要确定的问题](../open-questions.md) 的一览里加一行，指到提议。
状态用这几种：**讨论中**、**已采纳**、**不采纳**、**搁置**。

## 整理以后

- 每一条按内容挪走：
  - 定下来的规则：给它一个编号（提议用提议里的问题编号；第 k 次试玩意见的第 n 条是 Fk.n），
    在 [决定记录](../design/decision-log.md) 加一行，
    再写进 [design/game-design.md](../design/game-design.md) 的正文，括号里标上编号；改了原型的话，也更新 `design/current-rules.md`。
  - 要做的事：写进 [路线图](../roadmap.md)。
  - 说不清、要再问的：在 [要确定的问题](../open-questions.md) 加一条。
  - 做完的：写进 [开发日志](../devlog/README.md)。
- 原文不删，在每条后面注明改了哪里，状态改成「已整理」（意见）或「已采纳」「不采纳」「搁置」（提议），并更新下面的列表。
- 重要的决定再记一条 [decisions/](../decisions/README.md)。

## 列表

新的加在最后。

| 提出 | 文件 | 谁提的 | 状态 | 内容 |
| --- | --- | --- | --- | --- |
| 2026-10-05 | [light-speed-and-intel.md](light-speed-and-intel.md) | E7F6 | 已采纳（2026-10-06） | 光速、单位加速度、光粒库存、广播按光速传播、视野、航迹和情报。结论在 [游戏设计](../design/game-design.md) §3、§4、§6、§8，这里留草图和问题 G1～G13 的问答 |
| 2026-10-05 | [tech-tree.md](tech-tree.md) | E7F6 | 已采纳（2026-10-06） | 科技树（0～3 级）、建造和调度两栏、同时有多个单位。结论在 [游戏设计](../design/game-design.md) §1～§9，这里留科技树原图和问题 T1～T16 的问答；后来的 T17～T23 已定，讨论在 [存档](../design/archive/decided-questions-2026-10.md)。采纳后又改过几处，以游戏设计为准 |
| 2026-10-06 | [feedback-play-test-1.md](feedback-play-test-1.md) | E7F6 | 已整理（2026-10-06） | 第一次试玩新规则：开局位置、AI 有没有偷看、星图不直观、殖民船和星舰提前、能量太少 |
| 2026-10-06 | [feedback-play-test-2.md](feedback-play-test-2.md) | E7F6 | 已整理（2026-10-06） | 能量又太多；I、II 级的开放条件，II 级一定比 I 级晚；III 级门槛降到 25E；有广播器才能听广播 |
| 2026-10-07 | [feedback-play-test-3.md](feedback-play-test-3.md) | E7F6 | 已整理（2026-10-07） | 母星系至少隔开 5 格；采矿船每个星系最多 5 艘；能量够用了；比不过 AI 发二向箔 |
| 2026-10-07 | [feedback-play-test-4.md](feedback-play-test-4.md) | E7F6（网格只画视野内是 RainZL 提的） | 已整理（2026-10-07） | 视角和快捷键；网格改点阵或只画视野内；航线更明显；宜居星系要看到过才知道，殖民船可以盲飞；说明文字精炼 |
| 2026-10-07 | [feedback-play-test-5.md](feedback-play-test-5.md) | E7F6 | 已整理（2026-10-07） | 广播球挡视线；降到零维要有动画；预警把单向著也叫二向箔，隐藏文明按维度换武器 |
| 2026-10-07 | [feedback-play-test-6.md](feedback-play-test-6.md) | E7F6 | 已整理（2026-10-07） | 不是每局都赢；AI 打完躲进黑域，外面殖民地被打光后被自己的黑域包住；黑域慢慢扩散、每格有自己光速的想法（整理成 G14，已定） |
| 2026-10-07 | [feedback-play-test-7.md](feedback-play-test-7.md) | E7F6（原著武器资料是 RainZL 找的） | 已整理（2026-10-07） | 战舰带反物质打战舰和星舰；以后加粒子束、星际鱼雷、次声波氢弹，之后造的战舰自动带上（整理成 T23，武器已定；带反物质还没定，见 [T24](../open-questions.md#t24-战舰带反物质)） |
| 2026-10-08 | [dimension-followup-tasks.md](dimension-followup-tasks.md) | E7F6、RainZL、hrwu1、ccl | 大部分已采纳（2026-10-08） | 降维后续需求、验收条件与参考图。定下的是 U2～U6；做到哪一步见[路线图](../roadmap.md)；还没定的挪到 [E10～E13](../design/archive/open-questions-before-v01.md#一览) |
| 2026-10-09 | [interface-clarity.md](interface-clarity.md) | 用户 | 已采纳 | 全屏横向科技树、图例默认收起、减少广播圈和中盘显示层次。 |
| 2026-10-10 | [long-game-performance.md](long-game-performance.md) | RainZL | 讨论中 | 长局越来越慢的原因（广播光线在格子边界停、移动目标的观测每次采样都重发）和 P1～P5 建议，引用《游戏编程模式》。 |

- [V0.1 授权输入与实施边界](v01-authorized-input.md)：正式设计、III 侦察战报确认与后续验收要求。
