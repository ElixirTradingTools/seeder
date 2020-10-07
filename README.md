# Seeder

A tool for downloading market data to a sqlite database.

```elixir
Seeder.new(
    "AAPL",
    {1, :minute},
    {Seeder.date(%Date{year: 2018, month: 1, day: 1}), Seeder.now()},
    "/your/data/path",
    "****"
)
|> Seeder.dl_to_db(:ameritrade)
```

## Docs For Data Provider API's

Polygon:  
`https://polygon.io/docs/#get_v2_aggs_ticker__ticker__range__multiplier___timespan___from___to__anchor`

Ameritrade:  
`https://developer.tdameritrade.com/price-history/apis/get/marketdata/%7Bsymbol%7D/pricehistory`
