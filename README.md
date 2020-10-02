# Seeder

A tool for downloading market data to a sqlite database.

```elixir
%Seeder.Conf{
    ticker: "AAPL",
    start: %Date{year: 2018, month: 1, day: 1},
    end: %Date{year: 2020, month: 10, day: 1},
    period_size: 1,
    period_unit: :minute,
    db_root: "/your/data/path",
    api_key: "****"
}
|> Seeder.dl_to_db(:ameritrade)
```
