## 导入

导入负责把文件解析到数据库，

当点击导入后，用户手动选择解析方式

- ai_parser：就是发文本给 AI
- map_parser：这依赖干净且键正确的文件，所以功能很少用到
- alipay_parser：CSV
- wechat_parser：XLSX

## ai

openai 兼容 API，只处理文本
