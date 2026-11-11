:ok =
  :logger.set_handler_config(
    :default,
    :formatter,
    Logger.Formatter.new(
      format: "$date $time $metadata[$level] $message\n",
      metadata: [:request_id]
    )
  )

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(KeystonePhoenix.Repo, :manual)
