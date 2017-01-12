defmodule BatchTest do
  use XandraTest.IntegrationCase

  alias Xandra.{Batch, Error, Void}

  setup_all %{keyspace: keyspace} do
    {:ok, conn} = Xandra.start_link()
    Xandra.execute!(conn, "USE #{keyspace}")

    statement = "CREATE TABLE users (id int, name text, PRIMARY KEY (id))"
    Xandra.execute!(conn, statement)

    :ok
  end

  setup %{conn: conn} do
    Xandra.execute!(conn, "TRUNCATE users")
    :ok
  end

  test "batch of type \"logged\"", %{conn: conn} do
    statement = "INSERT INTO users (id, name) VALUES (:id, :name)"
    prepared_insert = Xandra.prepare!(conn, statement)

    batch =
      Batch.new(:logged)
      |> Batch.add("INSERT INTO users (id, name) VALUES (1, 'Marge')")
      |> Batch.add(prepared_insert, [2, "Homer"])
      |> Batch.add("INSERT INTO users (id, name) VALUES (?, ?)", [{"int", 3}, {"text", "Lisa"}])
      |> Batch.add("DELETE FROM users WHERE id = ?", [{"int", 3}])

    assert {:ok, %Void{}} = Xandra.execute(conn, batch)

    {:ok, result} = Xandra.execute(conn, "SELECT name FROM users", [])
    assert Enum.to_list(result) == [
      %{"name" => "Marge"},
      %{"name" => "Homer"},
    ]
  end

  test "batch of type \"unlogged\"", %{conn: conn} do
    batch =
      Batch.new(:unlogged)
      |> Batch.add("INSERT INTO users (id, name) VALUES (1, 'Rick')")
      |> Batch.add("INSERT INTO users (id, name) VALUES (2, 'Morty')")
    assert {:ok, %Void{}} = Xandra.execute(conn, batch)

    result = Xandra.execute!(conn, "SELECT name FROM users")
    assert Enum.to_list(result) == [
      %{"name" => "Rick"},
      %{"name" => "Morty"},
    ]
  end

  test "using a default timestamp for the batch", %{conn: conn} do
    timestamp = System.system_time(:seconds) - (_10_minutes = 600)
    batch =
      Batch.new()
      |> Batch.add("INSERT INTO users (id, name) VALUES (1, 'Abed')")
      |> Batch.add("INSERT INTO users (id, name) VALUES (2, 'Troy')")

    assert {:ok, %Void{}} = Xandra.execute(conn, batch, timestamp: timestamp)

    result = Xandra.execute!(conn, "SELECT name, WRITETIME(name) FROM users")
    assert Enum.to_list(result) == [
      %{"name" => "Abed", "writetime(name)" => timestamp},
      %{"name" => "Troy", "writetime(name)" => timestamp},
    ]
  end

  test "errors when there are bad queries in the batch", %{conn: conn} do
    # Only INSERT, UPDATE, and DELETE statements are allowed in BATCH queries.
    invalid_batch = Batch.add(Batch.new(), "SELECT * FROM users")
    assert {:error, %Error{reason: :invalid}} = Xandra.execute(conn, invalid_batch)
  end

  test "empty batch", %{conn: conn} do
    assert {:ok, %Void{}} = Xandra.execute(conn, Batch.new())
  end
end
