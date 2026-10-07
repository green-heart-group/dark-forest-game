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
