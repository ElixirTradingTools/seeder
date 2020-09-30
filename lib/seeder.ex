defmodule Seeder do
  alias __MODULE__.Conf
  use TypedStruct

  # %Conf{
  #   ticker: "MSFT",
  #   start: %Date{year: 2018, month: 1, day: 1},
  #   end: %Date{year: 2020, month: 10, day: 1},
  #   period_size: 1,
  #   period_unit: :minute,
  #   db_root: Path.join(File.cwd!(), "data"),
  #   api_key: "********************",
  # }

  typedstruct module: Conf do
    field :ticker, String.t()
    field :api_key, String.t()
    field :period_size, pos_integer(), default: 1
    field :period_unit, :second | :minute | :hour | :day | :week | :month | nil
    field :start, Date.t()
    field :end, Date.t()
    field :db_root, String.t() | nil, default: nil
  end

  @polygon_url 'https://api.polygon.io/v2/aggs/ticker'
  @ameritrade_url 'https://api.tdameritrade.com/v1/marketdata'

  def get_ameritrade_path(%Conf{
        ticker: sym,
        api_key: key,
        period_size: period_n,
        period_unit: period_u
      }) do
    ["apikey=#{key}", "frequencyType=#{period_u}", "frequency=#{period_n}"]
    |> Enum.join("&")
    |> case do
      query_string ->
        "#{@ameritrade_url}/#{sym}/pricehistory?#{query_string}"
    end
    |> to_charlist()
  end

  def convert_map_keys_to_atoms(map) do
    map
    |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
    |> Map.new()
  end

  def ameritrade_dl(conf = %Conf{}) do
    conf
    |> get_ameritrade_path()
    |> :httpc.request()
    |> case do
      {:ok, {_response, _headers, body}} -> body
    end
    |> to_string()
    |> Jason.decode!()
    |> Map.get("candles")
    |> Enum.map(fn
      %{"open" => o, "high" => h, "low" => l, "close" => c, "volume" => v, "datetime" => t} ->
        %{t: t, o: "#{o}", h: "#{h}", l: "#{l}", c: "#{c}", v: v}
    end)
  end

  def polygon_dl(%Conf{
        ticker: sym,
        api_key: api_key,
        start: start_date,
        end: end_date,
        period_size: time_n,
        period_unit: time_u
      }) do
    start_date = Date.to_iso8601(start_date)
    end_date = Date.to_iso8601(end_date)
    path = Enum.join([sym, "range", time_n, time_u, start_date, end_date], "/")

    '#{@polygon_url}/#{path}?apiKey=#{api_key}'
    |> :httpc.request()
    |> case do
      {:ok, {_response, _headers, body}} -> body
    end
    |> to_string()
    |> Jason.decode!()
    |> Map.get("results")
    |> Enum.map(fn bar ->
      bar
      |> convert_map_keys_to_atoms()
      |> Map.drop([:vw])
    end)
  end

  def assets_db_handler(path) do
    path = if(is_nil(path), do: File.cwd!(), else: path)
    {:ok, proc} = Depo.open(or_create: Path.join([path, "assets.sqlite3"]))

    Depo.transact(proc, fn ->
      Depo.write(proc, "CREATE TABLE IF NOT EXISTS assets (name TEXT, blob BLOB)")

      Depo.teach(proc, %{
        add: "INSERT OR REPLACE INTO assets VALUES (?1, ?2)",
        all: "SELECT * FROM assets",
        get: "SELECT * FROM assets WHERE name = ?1 LIMIT 1",
        find: "SELECT * FROM assets WHERE blob LIKE '%\"' || ?1 || '\":' || ?2 || '%' LIMIT 1"
      })
    end)

    {:ok, proc}
  end

  def chart_db_handler(%Conf{
        db_root: path,
        period_unit: period_unit,
        period_size: period_size,
        ticker: symbol
      }) do
    path = if(is_nil(path), do: File.cwd!(), else: path) |> Path.join(symbol)

    if !File.dir?(path) do
      if(File.mkdir(path) != :ok, do: {:error, :invalid_path})
    end

    i6l = "#{period_unit}_#{period_size}"

    {:ok, db} = Depo.open(or_create: Path.join([path, "#{i6l}.sqlite3"]))

    Depo.transact(db, fn ->
      Depo.write(
        db,
        "CREATE TABLE IF NOT EXISTS chart (t INTEGER PRIMARY KEY, o TEXT, h TEXT, l TEXT, c TEXT, v INTEGER)"
      )

      Depo.teach(db, %{
        add: "INSERT OR REPLACE INTO chart VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        all: "SELECT * FROM chart"
      })
    end)

    {:ok, db}
  end

  def dl_to_db(conf, api_service) when api_service in [:polygon, :ameritrade] do
    if(!File.dir?(conf.db_root), do: {:error, :invalid_db_root})

    {:ok, db} = chart_db_handler(conf)

    bars =
      case api_service do
        :polygon -> polygon_dl(conf)
        :ameritrade -> ameritrade_dl(conf)
      end

    Enum.each(bars, fn %{t: t, o: o, h: h, l: l, c: c, v: v} ->
      Depo.write(db, :add, [t, "#{o}", "#{h}", "#{l}", "#{c}", v])
    end)

    Process.exit(db, :normal)
    {:ok, "wrote #{length(bars)} records"}
  end
end
