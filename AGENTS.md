# AGENTS(raystyle/herdr-mirror)

> 本档现只立缺陷反馈纪律(REQ-057 对齐,fork 轻量形);其余工程合同未立档,勿顺手在此扩面。

## Must

- **缺陷反馈统一走舰队 issue 入口**(REQ-057,issues.ohmygh.com):`omc issue new "<标题>" --tool herdr --body "<描述>"`
  - body 首行带实际版本(如 `herdr-mirror 0.4.3`,取 Cargo.toml / herdr-plugin.toml)——代发时 version 字段记的是 omc 自身版本,本仓版本以 body 为准
  - 缺陷描述带仓内证据:触发命令、daemon/pane 状态、复现步;涉及远端 host 只记 hosts.toml 条目别名
  - 发前查重 `omc issue list --tool herdr`;详情 `omc issue show <id>`
- 提交纪律:推送前过评审闸门(evo-herdr:herdr-review);发布面改动遵 build-release 标准对齐批次的裁定

## Must not

- 不在本仓自建 issue 子命令面:本仓 REQ-057 裁形 = fork 轻量形(omc 代发);herdr CLI 原生 issue 子命令(tool=herdr)属 herdr 仓对齐面,不属本仓
- 隐私不外发:hosts.toml 地址、SSH 凭据、内网主机名不入 issue 标题与正文
