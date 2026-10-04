- 交易时间：xxxx-xx-xx
- 交易类型：对应招行交易摘要，支付宝付款方式
- 交易对象
- 交易商品
- 交易货币：CNY
- 交易收支：这个主要是独立出来好筛选
- 交易金额：填正数就行
- 交易分类：有三种方式，支付宝自带的，根据商家规则匹配的，自定义的，这就是普通的 TEXT

```sql
CREATE TABLE IF NOT EXISTS transactions (
    id              INTEGER PRIMARY KEY,
    date            TEXT    NOT NULL,
    currency        TEXT    NOT NULL DEFAULT 'CNY',
    type            TEXT,
    counterparty    TEXT,
    item            TEXT,
    direction       TEXT    NOT NULL CHECK (direction IN ('income', 'expense')),
    cents    INTEGER NOT NULL CHECK (cents > 0),
    category        TEXT
)
```
