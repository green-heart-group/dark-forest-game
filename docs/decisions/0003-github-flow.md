# 0003 分支和合并：用 GitHub Flow

状态：已决定（2026-10-07），先试用

## 背景

之前大家在一个长期的开发分支 `feature/prototype` 上做，有时也直接往 `master` 推，`master` 上积了很多零碎的提交，
和开发分支的关系也乱了。2026-10-07 整理了一次：

- `master` 的历史压成三个提交：hrwu1 之前的、hrwu1 的、hrwu1 之后的，文件内容不变。
- 原来的 81 个细小提交都留在 `archive/prototype` 分支上，要查某行代码当时为什么这样改，去那里看。
- `feature/prototype` 删掉了。

## 考虑过的选项

- **Git Flow**：一条长期的开发分支加 `master`，`master` 只接收发版。分支多，规矩多，适合同时维护好几个旧版本的软件。
- **长期开发分支，发版时 squash 进 `master`**：squash 是把很多提交压成一个再合并。
  每次发版后开发分支都和 `master` 脱节，下次合并会冲突，要额外处理。
- **GitHub Flow**：只有 `master` 一条长期分支，每件事开一个短的分支，通过 PR 合并。现在大多数团队用这种。

## 决定

用 GitHub Flow：

- `master` 随时能运行、能发布。不直接往 `master` 推，改动都通过 PR（pull request，在 GitHub 上请求把一个分支合并进来）。
- 每件事从 `master` 开一个新分支，名字写清楚做什么，例如 `fix/black-domain-speed`、`docs/feedback-8`。
  分支尽量短，几天内合并，合并完删掉。
- PR 只能用 squash 合并，`master` 上一件事一个提交。提交标题后面会自动带上 PR 编号，例如 `(#12)`，
  点进去能看到原来的每个小提交和讨论。
- 发版在 `master` 上打标签（见 [README 的发布](../../README.md#发布)），版本看标签，不看提交个数。

`master` 的保护规则（GitHub 仓库 Settings → Rules）：

- 不能强制推送，不能删除。
- 必须通过 PR 合并，不需要别人审批，自己可以合并自己的 PR。
- 测试（[`.github/workflows/test.yml`](../../.github/workflows/test.yml) 里的 `tests`）通过才能合并。

## 日常步骤

```bash
# 1. 从最新的 master 开分支
git switch master
git pull
git switch -c fix/black-domain-speed

# 2. 改代码、提交、推上去
git push -u origin fix/black-domain-speed

# 3. 开 PR，等测试通过后在网页上点「Squash and merge」，再删掉分支
gh pr create --fill

# 4. 回到 master，拉下合并后的结果，删掉本地分支
git switch master
git pull
git branch -D fix/black-domain-speed
```

只改一两个文档时，也可以直接在 GitHub 网页上编辑，保存时选「Create a new branch」，网页会帮你开 PR。

PR 合并以前 `master` 又有了新提交，并且和你改的地方冲突时，在自己的分支上运行 `git merge origin/master`，解决冲突后再推。

## 理由

- 只有一条长期分支，不会出现开发分支和 `master` 脱节的问题。
- 每个 PR 单独跑测试，坏的改动进不了 `master`。
- `master` 上一件事一个提交，看得清楚，出了问题也好退回。
- 团队只有三个人，审批会拖慢进度，先不要求；以后人多了再加。
