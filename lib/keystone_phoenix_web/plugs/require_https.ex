defmodule KeystonePhoenixWeb.Plugs.RequireHttps do
  @moduledoc "在生产入口拒绝没有 HTTPS 证明的请求。"

  import Plug.Conn

  @doc "返回 Plug 初始化参数。"
  def init(opts), do: opts

  @doc "生产配置开启时要求原始请求或受信转发协议使用 HTTPS。"
  def call(conn, _opts) do
    if Application.get_env(:keystone_phoenix, :force_ssl_enabled, false) and not https?(conn) do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("x-frame-options", "DENY")
      |> send_resp(
        426,
        Jason.encode!(
          KeystonePhoenixWeb.ApiResponse.error(:authorization_unavailable, "HTTPS is required")
        )
      )
      |> halt()
    else
      conn
    end
  end

  defp https?(conn) do
    conn.scheme == :https or
      (trusted_proxy?(conn) and forwarded_https?(conn))
  end

  defp forwarded_https?(conn) do
    Enum.any?(get_req_header(conn, "x-forwarded-proto"), fn value ->
      case String.split(value, ",") do
        [first | _] -> String.trim(first) == "https"
        _ -> false
      end
    end)
  end

  defp trusted_proxy?(conn) do
    peer = Plug.Conn.get_peer_data(conn).address

    Application.get_env(:keystone_phoenix, :trusted_proxy_cidrs, [])
    |> Enum.any?(&cidr_matches?(peer, &1))
  end

  defp cidr_matches?(peer, cidr) when is_tuple(peer) and is_binary(cidr) do
    case String.split(cidr, "/", parts: 2) do
      [network] -> cidr_matches?(peer, network, nil)
      [network, prefix] -> cidr_matches?(peer, network, parse_prefix(prefix))
      _ -> false
    end
  end

  defp cidr_matches?(_peer, _cidr), do: false

  defp cidr_matches?(peer, network, prefix) do
    with {:ok, network_address} <- :inet.parse_address(String.to_charlist(network)),
         true <- tuple_size(peer) == tuple_size(network_address),
         element_bits <- if(tuple_size(peer) == 4, do: 8, else: 16),
         bits <- tuple_size(peer) * element_bits,
         prefix when is_integer(prefix) <- prefix || bits,
         true <- prefix >= 0 and prefix <= bits do
      peer
      |> tuple_to_bits()
      |> same_network?(tuple_to_bits(network_address), prefix)
    else
      _ -> false
    end
  end

  defp parse_prefix(value) do
    case Integer.parse(value) do
      {prefix, ""} -> prefix
      _ -> nil
    end
  end

  defp tuple_to_bits(tuple) do
    element_bits = if(tuple_size(tuple) == 4, do: 8, else: 16)

    tuple
    |> Tuple.to_list()
    |> Enum.map(&<<&1::unsigned-integer-size(element_bits)>>)
    |> IO.iodata_to_binary()
  end

  defp same_network?(peer, network, prefix) do
    <<peer_prefix::bitstring-size(^prefix), _::bitstring>> = peer
    <<network_prefix::bitstring-size(^prefix), _::bitstring>> = network
    peer_prefix == network_prefix
  end
end
