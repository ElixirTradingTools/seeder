# Seeder

A tool for downloading market data to a sqlite database.

```elixir
conf = Seeder.new(
    "AAPL",
    {1, :minute},
    {Seeder.date(%Date{year: 2018, month: 1, day: 1}), Seeder.now()},
    System.get_env("TRADE_DB_PATH"),
    System.get_env("AMERITRADE_API_KEY")
)

{:ok, results} = conf |> Seeder.ameritrade_dl()

results |> Enum.at(-1) |> Map.get(:t) |> DateTime.from_unix(:millisecond)
```

## Docs For Data Provider API's

Polygon:  
`https://polygon.io/docs/#get_v2_aggs_ticker__ticker__range__multiplier___timespan___from___to__anchor`

Ameritrade:  
`https://developer.tdameritrade.com/price-history/apis/get/marketdata/%7Bsymbol%7D/pricehistory`
