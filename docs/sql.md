- 交易时间：xxxx-xx-xx
- 交易类型：对应招行交易摘要，支付宝付款方式
- 交易对象
- 交易商品
- 交易货币：CNY
- 交易收支：这个主要是独立出来好筛选
- 交易金额：填正数就行
- 交易分类：有三种方式，支付宝自带的，根据商家规则匹配的，自定义的，这就是普通的 TEXT

```sql
CREATE TABLE IF NOT EXISTS entries (
    id              TEXT    PRIMARY KEY,
    date            TEXT    NOT NULL,
    type            TEXT,
    counterparty    TEXT,
    item            TEXT,
    currency        TEXT    NOT NULL DEFAULT 'CNY',
    transaction     TEXT    NOT NULL CHECK (transaction IN ('income', 'expense')),
    amount          INTEGER NOT NULL CHECK (amount > 0),
    category        TEXT,
)
CREATE TABLE IF NOT EXISTS icons (
    category  TEXT PRIMARY KEY,
    icon TEXT NOT NULL
)
CREATE TABLE IF NOT EXISTS rules (
    name   TEXT PRIMARY KEY,
    date            TEXT    NOT NULL,
    type            TEXT    NOT NULL,
    counterparty    TEXT    NOT NULL,
    item            TEXT    NOT NULL,
    currency        TEXT,
    transaction     TEXT    NOT NULL,
    amount          INTEGER NOT NULL,
    category        TEXT,
)
```

`id` 用 uuidv7（RFC 9562），由 `uuid` 包生成：前 48 位是毫秒时间戳，所以字典序就是时间序。
同一个毫秒内生成的多行之间没有先后保证（那 74 位是纯随机）。
