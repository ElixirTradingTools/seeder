defmodule Seeder do
  alias __MODULE__.Conf
  use TypedStruct

  @type t :: %Conf{
          ticker: String.t(),
          api_key: String.t(),
          interval_size: pos_integer(),
          interval_unit: :second | :minute | :hour | :day | :week | :month,
          start: DateTime.t(),
          end: DateTime.t(),
          db_root: String.t() | nil
        }

  typedstruct module: Conf do
    field :ticker, String.t(), enforce: true
    field :api_key, String.t(), enforce: true
    field :interval_size, pos_integer(), default: 1, enforce: true

    field :interval_unit, :second | :minute | :hour | :day | :week | :month,
      default: :minute,
      enforce: true

    field :start, DateTime.t(), enforce: true
    field :end, DateTime.t(), enforce: true
    field :db_root, String.t() | nil, default: nil, enforce: true
  end

  @valid_intervals [:second, :minute, :hour, :day, :week, :month]
  @polygon_url 'https://api.polygon.io/v2/aggs/ticker'
  @ameritrade_url 'https://api.tdameritrade.com/v1/marketdata'

  def tz, do: Tzdata.TimeZoneDatabase
  def now, do: DateTime.now!("America/New_York", tz())

  # Seeder.new(
  #   "MSFT",
  #   :minute,
  #   1,
  #   Seeder.date(%Date{year: 2018, month: 1, day: 1}),
  #   Seeder.now(),
  #   Path.join(File.cwd!(), "data")
  #   "********************",
  # )

  def new(sym, i6l_u, i6l_n, start_dt = %DateTime{}, end_dt = %DateTime{}, path, api_key)
      when is_binary(sym) and
             is_binary(api_key) and
             i6l_u in @valid_intervals and
             is_integer(i6l_n) and
             i6l_n > 0 and
             is_binary(path) do
    if !File.dir?(path) do
      {:error, :invalid_data_path}
    else
      {:ok,
       %Conf{
         ticker: sym,
         api_key: api_key,
         interval_size: i6l_n,
         interval_unit: i6l_u,
         start: start_dt,
         end: end_dt,
         db_root: path
       }}
    end
  end

  def date(%Date{year: y, month: m, day: d}) do
    %DateTime{
      year: y,
      month: m,
      day: d,
      hour: 0,
      minute: 0,
      second: 0,
      zone_abbr: "ET",
      std_offset: 0,
      utc_offset: -4,
      time_zone: "America/New_York"
    }
  end

  def get_ameritrade_path(%Conf{
        ticker: sym,
        api_key: key,
        interval_size: interval_n,
        interval_unit: interval_u,
        start: start_date,
        end: end_date
      })
      when is_binary(sym) and interval_u in @valid_intervals do
    start_date = DateTime.to_unix(start_date, :millisecond)
    end_date = DateTime.to_unix(end_date, :millisecond)

    case interval_u do
      :minute -> {:ok, "minute"}
      :day -> {:ok, "day"}
      :month -> {:ok, "month"}
      n -> {:error, "Interval `#{n}` is not supported with Ameritrade API"}
    end
    |> case do
      {:error, reason} ->
        {:error, reason}

      {:ok, interval_u} ->
        [
          "apikey=#{key}",
          "startDate=#{start_date}",
          "endDate=#{end_date}",
          "frequencyType=#{interval_u}",
          "frequency=#{interval_n}"
        ]
        |> Enum.join("&")
        |> (fn query_str -> {:ok, '#{@ameritrade_url}/#{sym}/pricehistory?#{query_str}'} end).()
    end
  end

  def ameritrade_dl(conf = %Conf{}) do
    conf
    |> get_ameritrade_path()
    |> case do
      {:error, reason} ->
        {:error, reason}

      {:ok, path} ->
        path
        |> :httpc.request()
        |> (fn {:ok, {_response, _headers, body}} -> body end).()
        |> to_string()
        |> Jason.decode!()
        |> Map.get("candles")
        |> Enum.map(fn
          %{"open" => o, "high" => h, "low" => l, "close" => c, "volume" => v, "datetime" => t} ->
            %{t: t, o: "#{o}", h: "#{h}", l: "#{l}", c: "#{c}", v: v}
        end)
        |> (fn bars -> {:ok, bars} end).()
    end
  end

  def polygon_dl(%Conf{
        ticker: sym,
        api_key: api_key,
        start: start_date,
        end: end_date,
        interval_size: interval_n,
        interval_unit: interval_u
      })
      when interval_u in @valid_intervals do
    start_date = Date.to_iso8601(start_date)
    end_date = Date.to_iso8601(end_date)

    case interval_u do
      # :second -> {:ok, "second"}
      :minute -> {:ok, "minute"}
      :hour -> {:ok, "hour"}
      :day -> {:ok, "day"}
      :week -> {:ok, "week"}
      :month -> {:ok, "month"}
      n -> {:error, "Interval value #{n} is not supported with Polygon API"}
    end
    |> case do
      {:ok, interval_u} ->
        [sym, "range", interval_n, interval_u, start_date, end_date]
        |> Enum.join("/")
        |> (fn str -> '#{@polygon_url}/#{str}?apiKey=#{api_key}' end).()
        |> :httpc.request()
        |> (fn {:ok, {_response, _headers, body}} -> body end).()
        |> to_string()
        |> Jason.decode!()
        |> Map.get("results")
        |> Enum.map(fn
          %{"datetime" => t, "open" => o, "high" => h, "low" => l, "close" => c, "volume" => v} ->
            %{t: t, o: "#{o}", h: "#{h}", l: "#{l}", c: "#{c}", v: v}
        end)

      {:error, reason} ->
        {:error, reason}
    end
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
        interval_unit: interval_unit,
        interval_size: interval_size,
        ticker: symbol
      }) do
    path = if(is_nil(path), do: File.cwd!(), else: path) |> Path.join(symbol)

    if !File.dir?(path) do
      if(File.mkdir(path) != :ok, do: {:error, :invalid_data_path})
    end

    i6l = "#{interval_unit}_#{interval_size}"

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

  def dl_to_db(conf = %Conf{}, api_service) when api_service in [:polygon, :ameritrade] do
    if(!File.dir?(conf.db_root), do: {:error, :invalid_data_path})

    {:ok, db} = chart_db_handler(conf)

    case api_service do
      :polygon -> polygon_dl(conf)
      :ameritrade -> ameritrade_dl(conf)
    end
    |> case do
      {:error, reason} ->
        {:error, reason}

      {:ok, bars} ->
        Enum.each(bars, fn %{t: t, o: o, h: h, l: l, c: c, v: v} ->
          Depo.write(db, :add, [t, o, h, l, c, v])
        end)

        Process.exit(db, :normal)
        {:ok, "wrote #{length(bars)} records"}
    end
  end
end
