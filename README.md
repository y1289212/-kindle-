# Kindle 晋江阅读启动器 · 书架速返版

在已越狱的 Kindle Paperwhite 5（固件 5.19.2）上，从 Kindle 首页进入本项目的 Android 7.1.2 晋江阅读环境。已在维护者的一台设备验证。其他型号、固件和越狱启动方式需要单独验证。

读到一半想回 Kindle 首页？在阅读页右上角轻点三下。下次还想接着读，点同一个晋江入口即可。设备重启后的首次打开仍需冷启动。

公开版本标签为 `v0.1.0`，对应内部构建 `v116-fix2`。

## 已有配套 v115 或 v116 环境的读者

需要能从 Kindle 首页执行 documents 下的 shell 脚本，并已有配套的 kindle-system-test 目录、持久镜像及 services-v115.jar。仅有越狱或 KOReader 仍缺少本项目运行环境。

1. 完整关闭晋江会话，连接电脑，把 Kindle 的 documents 里现有的 kindle-jinjiang-v87.sh 和 kindle-jinjiang-v63-runtime.sh 备份到电脑。
2. 将 dist/kindle-jinjiang-quick-return-update.zip 解压到 Kindle 盘符根目录，合并 documents，覆盖两个同名脚本。保留两个脚本原名。
3. 安全弹出、拔线，在 Kindle 首页点 kindle-jinjiang-v87.sh。第一次冷启动需要等待。
4. 想稍后继续读，在阅读页右上角轻点三下。回到 Kindle 首页后可接电脑充电。会话保留期间普通 USB 盘符隐藏。拔线后再点同一入口即可返回。
5. 想正常传书，在晋江阅读页贴着最右边缘从顶部滑到底部，等完整退出，再连接电脑。
6. 回退时完整退出并恢复备份的两份脚本。当前阅读数据在 kindle-system-test/kindle-persistent-v62.img 内，升级或回退脚本均无需替换它。

实测一次冷启动至窗口获得焦点为 2 分 48 秒。一次 USB 插拔后，从处理恢复请求到输出画面为 2.53 秒，另一次普通恢复为 2.14 秒。设备重启后仍需冷启动。当前没有开机后台预启动或独立 USB 传书盘。

## 首装候选目录（已有依赖的维护者）

在 Windows 解压本发布包，进入 README 所在目录，连接含有配套运行文件的 Kindle。在 PowerShell 执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\assemble-candidate.ps1 -KindleRoot E:\
```

输出到电脑桌面的全新目录。预留至少 2.1 GiB 空间。工具按 payload-files.txt 复制 51 个输入，按 payload-sha256.csv 校验副本，其中包括与本启动器匹配的 services-v115.jar。它从固定哈希的 root-1536m-v35.img.gz 生成初始镜像，写入所有权标记和两个入口文件。出现 CANDIDATE_READY 才表示组装完成。输入不全或哈希不符时会停止。当前个人使用中的持久镜像不作为输入。请勿将输出的初始镜像覆盖到已有阅读进度的设备上。

没有这套依赖的读者目前可以查看启动器源码。晋江 APK、Android 镜像、字体、词库、内核模块和其他运行文件须另行准备。当前版本尚未在第二台从零部署的 Kindle 上验收。

## 许可与反馈

附带 MIT 许可证适用于项目原创脚本和文档。配套依赖各自适用原许可。本项目与 Amazon、晋江无隶属关系。分享本源码发布包即可；请勿打包自己的 Kindle 用户盘、账号数据、持久化镜像或含阅读画面的完整日志。反馈可摘录设备型号、固件、操作步骤和 result.txt 中对应的状态行。
