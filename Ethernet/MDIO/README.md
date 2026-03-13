# MDIO 接口驱动设计

本节记录如何通过 MDIO 接口配置 PHY 芯片寄存器。

项目代码存放在 `RTL` 目录下，分为源码和测试平台。

## 1、首先理解什么是 MDIO
MDIO (Management Data Input/Output), **管理数据**输入/输出接口，也叫 SMI (Serial Management Interface)。通过此接口读写PHY芯片的寄存器以获取或者修改当前PHY芯片的工作状态，例如复位、设置速度、双工和开启/关闭自协商状态等。

