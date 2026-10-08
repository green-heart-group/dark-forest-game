# 0003 分支和合并：用 GitHub Flow

状态：已决定（2026-10-07），先试用

GitHub Flow 是 GitHub 推荐的一种简单做法：

1. `master` 是唯一的长期分支，随时能运行、能发布。
2. 要做一件事，从 `master` 开一个新分支，名字写清楚做什么，例如 `fix/black-domain-speed`。
3. 在分支上提交，推到 GitHub。
4. 开 PR（pull request，请求把这个分支合并进 `master`），自动测试会跑；需要的话请别人看一看。
5. 测试通过后合并进 `master`，删掉这个分支。

这个仓库的设置：PR 只能用 squash 合并（把分支上的所有提交压成一个），不需要别人审批，测试通过才能合并；
`master` 不能直接推送、强制推送或删除。

## 分支名

分支名写成「前缀/做什么」，前缀说明是哪一类改动，后面用几个英文小写单词、中间用 `-` 连起来。
一个分支做了几类事时，按最主要的那类选前缀。

| 前缀 | 用在什么时候 | 例子 |
| --- | --- | --- |
| `feature/` | 加新功能、新规则 | `feature/sophon` |
| `fix/` | 修错误 | `fix/black-domain-speed` |
| `test/` | 只加测试、改测试或测试工具 | `test/improve` |
| `docs/` | 只改文档 | `docs/current-rules` |
| `refactor/` | 整理代码，玩起来没有变化 | `refactor/split-main-gd` |
| `perf/` | 让程序跑得更快，结果不变 | `perf/vision-cache` |
| `balance/` | 只调数值（`balance.gd`、数值方案） | `balance/tier3-energy` |
| `chore/` | 杂事：改配置、升级 Godot 或工具、改 GitHub 上的自动流程 | `chore/ci-cache` |
| `experiment/` | 试一个想法，不一定合并 | `experiment/hex-grid` |

- 改名：`git branch -m 新名字`，再 `git push -u origin 新名字`，最后 `git push origin --delete 旧名字` 删掉远程的旧分支。
  已经开了 PR 的分支不要改名（GitHub 会关掉原来的 PR）。
- `archive/` 开头的分支只用来留着旧东西（比如 `archive/python`），不再改动，也不合并进 `master`。
- 别的项目常见的 `release/`、`hotfix/`（发布前整理、紧急修已发布的版本）在 GitHub Flow 里用不到：
  `master` 随时能发布，紧急的修复也是开一个 `fix/` 分支走 PR。
