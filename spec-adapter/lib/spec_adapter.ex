defmodule SpecAdapter do
  @moduledoc """
  Adapter that lets the Flagsmith SDK behavioural spec drive this SDK.

  Protocol: https://github.com/Flagsmith/sdk-spec/blob/main/ADAPTER.md
  """

  use Plug.Router
  use Plug.ErrorHandler

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], pass: ["*/*"], json_decoder: Jason)
  plug(:dispatch)

  get "/health" do
    {:ok, version} = :application.get_key(:flagsmith_engine, :vsn)
    send_json(conn, 200, %{sdk: "flagsmith-elixir-client", version: to_string(version)})
  end

  post "/clients" do
    %{"environmentKey" => environment_key, "apiUrl" => api_url} = conn.body_params
    config = Flagsmith.Client.new(environment_key: environment_key, api_url: api_url)
    client_id = Agent.get_and_update(SpecAdapter.Clients, &store_client(&1, config))
    send_json(conn, 201, %{clientId: client_id})
  end

  post "/clients/:client_id/environment-flags" do
    with_client(conn, client_id, fn config ->
      Flagsmith.Client.get_environment_flags(config)
    end)
  end

  post "/clients/:client_id/identity-flags" do
    %{"identifier" => identifier} = conn.body_params

    traits =
      for {key, value} <- conn.body_params["traits"] || %{},
          do: %{"trait_key" => key, "trait_value" => value}

    with_client(conn, client_id, fn config ->
      Flagsmith.Client.get_identity_flags(config, identifier, traits)
    end)
  end

  delete "/clients/:client_id" do
    Agent.update(SpecAdapter.Clients, fn state ->
      Map.update!(state, :clients, &Map.delete(&1, client_id))
    end)

    send_resp(conn, 204, "")
  end

  match _ do
    send_json(conn, 404, %{error: "No route for #{conn.method} #{conn.request_path}"})
  end

  @impl Plug.ErrorHandler
  def handle_errors(conn, %{reason: reason}),
    do: send_json(conn, 500, %{error: Exception.format_banner(:error, reason)})

  defp store_client(%{next_id: id, clients: clients}, config) do
    client_id = Integer.to_string(id)
    {client_id, %{next_id: id + 1, clients: Map.put(clients, client_id, config)}}
  end

  defp with_client(conn, client_id, fun) do
    case Agent.get(SpecAdapter.Clients, &Map.fetch(&1.clients, client_id)) do
      {:ok, config} ->
        case fun.(config) do
          {:ok, flags} -> send_json(conn, 200, %{flags: serialise_flags(flags)})
          {:error, reason} -> send_json(conn, 500, %{error: inspect(reason)})
        end

      :error ->
        send_json(conn, 404, %{error: "Unknown client #{client_id}"})
    end
  end

  defp serialise_flags(flags) do
    for flag <- Flagsmith.Client.all_flags(flags) do
      %{featureName: flag.feature_name, enabled: flag.enabled, value: flag.value}
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
