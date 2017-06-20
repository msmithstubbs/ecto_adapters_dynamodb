defmodule Ecto.Adapters.DynamoDB do
  @moduledoc """
  Ecto adapter for Amazon DynamoDB

  Currently fairly limited subset of Ecto, enough for basic operations.

  NOTE: in ecto, Repo.get[!] ends up calling: 
    -> querable.get
    -> queryable.one
    -> queryable.all
    -> queryable.execute
    -> adapter.execute (possibly prepare somewhere in their too? trace.)


  """


  @behaviour Ecto.Adapter
  #@behaviour Ecto.Adapter.Storage
  #@behaviour Ecto.Adapter.Migration

  defmacro __before_compile__(_env) do
    # Nothing to see here, yet...

  end

  alias ExAws.Dynamo
  alias Ecto.Query.BooleanExpr

  # I don't think this is necessary: Probably under child_spec and ensure_all_started
  def start_link(repo, opts) do
    ecto_dynamo_log(:debug, "start_link repo: #{inspect repo} opts: #{inspect opts}")
    Agent.start_link fn -> [] end
  end


  ## Adapter behaviour - defined in lib/ecto/adapter.ex (in the ecto github repository)

  @doc """
  Returns the childspec that starts the adapter process.
  """
  def child_spec(repo, opts) do
    # TODO: need something here...
    # * Pull dynamo db connection options from config
    # * Start dynamo connector/aws libraries
    # we'll return our own start_link for now, but I don't think we actually need
    # an app here, we only need to ensure that our dependencies such as aws libs are started.
    # 
    import Supervisor.Spec
    child_spec = worker(__MODULE__, [repo, opts])
    ecto_dynamo_log(:debug, "child spec3. REPO: #{inspect repo}\n CHILD_SPEC: #{inspect child_spec}\nOPTS: #{inspect opts}")
    child_spec
  end


  @doc """
  Ensure all applications necessary to run the adapter are started.
  """
  def ensure_all_started(repo, type) do
    ecto_dynamo_log(:debug, "ensure all started: type: #{inspect type} #{inspect repo}")
    {:ok, [repo]}
  end


# moved to transaction.ex in ecto 2.1.4
#  def in_transaction?(_repo), do: false
#
#  def rollback(_repo, _value), do:
#    raise BadFunctionError, message: "#{inspect __MODULE__} does not support transactions."


  @doc """
  Called to autogenerate a value for id/embed_id/binary_id.

  Returns the autogenerated value, or nil if it must be
  autogenerated inside the storage or raise if not supported.
  """

  def autogenerate(:id), do: Ecto.UUID.bingenerate()
  def autogenerate(:embed_id), do: Ecto.UUID.generate()
  def autogenerate(:binary_id), do: Ecto.UUID.bingenerate()

  @doc """
  Returns the loaders for a given type.

  It receives the primitive type and the Ecto type (which may be
  primitive as well). It returns a list of loaders with the given
  type usually at the end.

  This allows developers to properly translate values coming from
  the adapters into Ecto ones. For example, if the database does not
  support booleans but instead returns 0 and 1 for them, you could
  add:

    def loaders(:boolean, type), do: [&bool_decode/1, type]
    def loaders(_primitive, type), do: [type]

    defp bool_decode(0), do: {:ok, false}
    defp bool_decode(1), do: {:ok, true}

  All adapters are required to implement a clause for `:binary_id` types,
  since they are adapter specific. If your adapter does not provide binary
  ids, you may simply use Ecto.UUID:

    def loaders(:binary_id, type), do: [Ecto.UUID, type]
    def loaders(_primitive, type), do: [type]

  """
  def loaders(_primitive, type), do: [type]



  @doc """
  Returns the dumpers for a given type.

  It receives the primitive type and the Ecto type (which may be
  primitive as well). It returns a list of dumpers with the given
  type usually at the beginning.

  This allows developers to properly translate values coming from
  the Ecto into adapter ones. For example, if the database does not
  support booleans but instead returns 0 and 1 for them, you could
  add:

    def dumpers(:boolean, type), do: [type, &bool_encode/1]
    def dumpers(_primitive, type), do: [type]

    defp bool_encode(false), do: {:ok, 0}
    defp bool_encode(true), do: {:ok, 1}

  All adapters are required to implement a clause or :binary_id types,
  since they are adapter specific. If your adapter does not provide
  binary ids, you may simply use Ecto.UUID:

    def dumpers(:binary_id, type), do: [type, Ecto.UUID]
    def dumpers(_primitive, type), do: [type]

  """
  def dumpers(:utc_datetime, datetime), do: [datetime, &to_iso_string/1]
  def dumpers(:naive_datetime, datetime), do: [datetime, &to_iso_string/1]
  def dumpers(_primitive, type), do: [type]

  # Add UTC offset
  # We are adding the offset here also for the :naive_datetime, this
  # assumes we are getting a UTC date (which does correspond with the
  # timestamps() macro but not necessarily with :naive_datetime in general)
  defp to_iso_string(datetime) do
    {:ok, (datetime |> Ecto.DateTime.cast! |> Ecto.DateTime.to_iso8601) <> "Z"}
  end

  @doc """
  Commands invoked to prepare a query for `all`, `update_all` and `delete_all`.

  The returned result is given to `execute/6`.
  """
  #@callback prepare(atom :: :all | :update_all | :delete_all, query :: Ecto.Query.t) ::
  #          {:cache, prepared} | {:nocache, prepared}
  def prepare(:all, query) do
    # 'preparing' is more a SQL concept - Do we really need to do anything here or just pass the params through?
    ecto_dynamo_log(:debug, "PREPARE:::")
    ecto_dynamo_log(:debug, inspect(query, structs: false))
    {:nocache, {:all, query}}
  end
  

  def prepare(:update_all, query) do
    ecto_dynamo_log(:debug, "PREPARE::UPDATE_ALL:::")
    ecto_dynamo_log(:debug, inspect(query, structs: false))
    {:nocache, {:update_all, query}}
  end
  # do: {:cache, {System.unique_integer([:positive]), @conn.update_all(query)}}


  def prepare(:delete_all, query) do
    ecto_dynamo_log(:debug, "PREPARE::DELETE_ALL:::")
    ecto_dynamo_log(:debug, inspect(query, structs: false))
    {:nocache, {:delete_all, query}}
  end
  # do: {:cache, {System.unique_integer([:positive]), @conn.delete_all(query)}}



  @doc """
  Executes a previously prepared query.

  It must return a tuple containing the number of entries and
  the result set as a list of lists. The result set may also be
  `nil` if a particular operation does not support them.

  The `meta` field is a map containing some of the fields found
  in the `Ecto.Query` struct.

  It receives a process function that should be invoked for each
  selected field in the query result in order to convert them to the
  expected Ecto type. The `process` function will be nil if no
  result set is expected from the query.
  """
  #@callback execute(repo, query_meta, query, params :: list(), process | nil, options) :: result when
  #          result: {integer, [[term]] | nil} | no_return,
  #          query: {:nocache, prepared} |
  #                 {:cached, (prepared -> :ok), cached} |
  #                 {:cache, (cached -> :ok), prepared}
  def execute(repo, meta, {:nocache, {func, prepared}}, params, process, opts) do
    ecto_dynamo_log(:debug, "EXECUTE... EXECUTING!=============================")
    ecto_dynamo_log(:debug, "REPO::: #{inspect repo, structs: false}")
    ecto_dynamo_log(:debug, "META::: #{inspect meta, structs: false}")
    ecto_dynamo_log(:debug, "PREPARED::: #{inspect prepared, structs: false}")
    ecto_dynamo_log(:debug, "PARAMS::: #{inspect params, structs: false}")
    ecto_dynamo_log(:debug, "PROCESS::: #{inspect process, structs: false}")
    ecto_dynamo_log(:debug, "OPTS::: #{inspect opts, structs: false}")

    {table, model} = prepared.from
    validate_where_clauses!(prepared)
    lookup_fields = extract_lookup_fields(prepared.wheres, params, [])

    limit_option = opts[:scan_limit]
    scan_limit = if is_integer(limit_option), do: [limit: limit_option], else: []
    updated_opts = Keyword.drop(opts, [:scan_limit, :limit]) ++ scan_limit

    ecto_dynamo_log(:debug, "table = #{inspect table}")
    ecto_dynamo_log(:debug, "lookup_fields: #{inspect lookup_fields}")
    ecto_dynamo_log(:debug, "scan_limit: #{inspect scan_limit}")

    case func do
      :delete_all ->
        ecto_dynamo_log(:info, "#{inspect __MODULE__}.execute: delete_all")
        ecto_dynamo_log(:info, "Table: #{inspect table}; Lookup fields: #{inspect lookup_fields}; Options: #{inspect updated_opts}")
        delete_all(table, lookup_fields, updated_opts)

      :update_all  -> 
        update_params = extract_update_params(prepared.updates, params)

        ecto_dynamo_log(:info, "#{inspect __MODULE__}.execute: update_all")
        ecto_dynamo_log(:info, "Table: #{inspect table}; Lookup fields: #{inspect lookup_fields}; Options: #{inspect updated_opts}; Update params: #{inspect update_params}")

        update_all(table, lookup_fields, updated_opts, update_params, model)

      :all ->
        ecto_dynamo_log(:info, "#{inspect __MODULE__}.execute")
        ecto_dynamo_log(:info, "Table: #{inspect table}; Lookup fields: #{inspect lookup_fields}; options: #{inspect updated_opts}")
        result = Ecto.Adapters.DynamoDB.Query.get_item(table, lookup_fields, updated_opts)
        ecto_dynamo_log(:debug, "result = #{inspect result}")

        if opts[:query_info_key], do: Ecto.Adapters.DynamoDB.QueryInfo.put(opts[:query_info_key], extract_query_info(result))

        if result == %{} do
          # Empty map means "not found"
          {0, []}
        else
          case result["Count"] do
            nil   -> decoded = result |> Dynamo.decode_item(as: model) |> custom_decode(model)
                     {1, [[decoded]]}
            _ ->
              # HANDLE .all(query) QUERIES

              decoded = Enum.map(result["Items"], fn(item) -> 
                [Dynamo.decode_item(%{"Item" => item}, as: model) |> custom_decode(model)]
              end)

              {length(decoded), decoded}
          end
        end
    end
  end

  # delete_all allows for the recursive option, scanning through multiple pages
  defp delete_all(table, lookup_fields, opts) do
    # select only the key
    {:primary, key_list} = Ecto.Adapters.DynamoDB.Info.primary_key!(table)
    scan_or_query = Ecto.Adapters.DynamoDB.Query.scan_or_query?(table, lookup_fields)
    recursive = Ecto.Adapters.DynamoDB.Query.parse_recursive_option(scan_or_query, opts)
    updated_opts = prepare_recursive_opts(opts ++ [projection_expression: Enum.join(key_list, ", ")])

    delete_all_recursive(table, lookup_fields, updated_opts, recursive, %{})
  end

  defp delete_all_recursive(table, lookup_fields, opts, recursive, query_info) do
    # query the table for which records to delete
    fetch_result = Ecto.Adapters.DynamoDB.Query.get_item(table, lookup_fields, opts)

    updated_query_info = case fetch_result do
      %{"Count" => last_count, "ScannedCount" => last_scanned_count} -> 
        %{"Count" => last_count + Map.get(query_info, "Count", 0),
          "ScannedCount" => last_scanned_count + Map.get(query_info, "ScannedCount", 0),
          "LastEvaluatedKey" => Map.get(fetch_result, "LastEvaluatedKey")}
      _ -> query_info
    end

    items = case fetch_result do
      %{"Items" => fetch_items} -> fetch_items
      %{"Item" => item}         -> [item]
      _                         -> []
    end

    prepared_data = for key_list <- Enum.map(items, &Map.to_list/1) do
      key_map = for {key, val_map} <- key_list, into: %{}, do: {key, hd Map.values(val_map)}
      [delete_request: [key: key_map]]
    end

    if prepared_data != [], do: batch_delete(table, prepared_data)

    updated_recursive = Ecto.Adapters.DynamoDB.Query.update_recursive_option(recursive)

    if fetch_result["LastEvaluatedKey"] != nil and updated_recursive.continue do
        opts_with_offset = opts ++ [exclusive_start_key: fetch_result["LastEvaluatedKey"]]
        delete_all_recursive(table, lookup_fields, opts_with_offset, updated_recursive.new_value, updated_query_info)
    else
      if opts[:query_info_key], do: Ecto.Adapters.DynamoDB.QueryInfo.put(opts[:query_info_key], updated_query_info)
      {updated_query_info["Count"], nil}
    end
  end

  defp batch_delete(table, prepared_data) do
    batch_write_attempt = Dynamo.batch_write_item(%{table => prepared_data}) |> ExAws.request |> handle_error!(%{table: table, records: []})

    cond do
      batch_write_attempt["UnprocessedItems"] == %{} ->
        :ok
        
      # TODO: handle unprocessed items?
      batch_write_attempt["UnprocessedItems"] != %{} ->
        raise "#{inspect __MODULE__}.delete_all: Handling not yet implemented for \"UnprocessedItems\" as a non-empty map. ExAws.Dynamo.batch_write_item response: #{inspect batch_write_attempt}"
    end
  end


  defp update_all(table, lookup_fields, opts, update_params, model) do
    scan_or_query = Ecto.Adapters.DynamoDB.Query.scan_or_query?(table, lookup_fields)
    recursive = Ecto.Adapters.DynamoDB.Query.parse_recursive_option(scan_or_query, opts)

    key_list = Ecto.Adapters.DynamoDB.Info.primary_key!(table)
    ecto_dynamo_log(:debug, "key_list: #{inspect key_list}")

    update_expression = construct_update_expression(update_params, opts)
    attribute_names = construct_expression_attribute_names(update_params)
    attribute_values = construct_expression_attribute_values(update_params, opts)

    base_update_options = [expression_attribute_names: attribute_names,
                           update_expression: update_expression,
                           return_values: :all_new]

    updated_opts = prepare_recursive_opts(opts)

    update_all_recursive(table, lookup_fields, updated_opts, base_update_options, key_list, attribute_values, model, recursive, %{})
  end

  defp update_all_recursive(table, lookup_fields, opts, base_update_options, key_list, attribute_values, model, recursive, query_info) do
    fetch_result = Ecto.Adapters.DynamoDB.Query.get_item(table, lookup_fields, opts)
    ecto_dynamo_log(:debug, "fetch_result: #{inspect fetch_result}")

    updated_query_info = case fetch_result do
      %{"Count" => last_count, "ScannedCount" => last_scanned_count} -> 
        %{"Count" => last_count + Map.get(query_info, "Count", 0),
          "ScannedCount" => last_scanned_count + Map.get(query_info, "ScannedCount", 0),
          "LastEvaluatedKey" => Map.get(fetch_result, "LastEvaluatedKey")}
      _ -> query_info
    end

    items = case fetch_result do
      %{"Items" => fetch_items} -> fetch_items
      %{"Item" => item}         -> [item]
      _                         -> []
    end

    if items != [],
    # We are not collecting the updated results, but we could.
    do: batch_update(table, items, key_list, base_update_options, attribute_values, model)

    updated_recursive = Ecto.Adapters.DynamoDB.Query.update_recursive_option(recursive)

    if fetch_result["LastEvaluatedKey"] != nil and updated_recursive.continue do
        opts_with_offset = opts ++ [exclusive_start_key: fetch_result["LastEvaluatedKey"]]
        update_all_recursive(table, lookup_fields, opts_with_offset, base_update_options, key_list, attribute_values, model, updated_recursive.new_value, updated_query_info)
    else
      if opts[:query_info_key], do: Ecto.Adapters.DynamoDB.QueryInfo.put(opts[:query_info_key], updated_query_info)
      {updated_query_info["Count"], []}
    end
  end

  defp batch_update(table, items, key_list, base_update_options, attribute_values, model) do
    Enum.reduce items, {0, []}, fn(result_to_update, acc) ->
      filters = get_key_values_dynamo_map(result_to_update, key_list)
      options = maybe_add_attribute_values(base_update_options, attribute_values)

      # 'options' might not have the key, ':expression_attribute_values', when there are only removal statements.
      record = if options[:expression_attribute_values], do: [options[:expression_attribute_values] |> Enum.into(%{})], else: []

      update_query_result = Dynamo.update_item(table, filters, options) |> ExAws.request |> handle_error!(%{table: table, records: record ++ []})

      {count, result_list} = acc
      {count + 1, [Dynamo.decode_item(update_query_result["Attributes"], as: model) |> custom_decode(model) | result_list]}
    end
  end


  # During delete_all's and update_all's recursive
  # procedure, we want to keep the recursion in
  # the top-level, between actions, rather than
  # load all the results into memory and then act;
  # so we disable the recursion on get_item
  defp prepare_recursive_opts(opts) do
    opts |> Keyword.delete(:page_limit) |> Keyword.update(:recursive, false, fn _ -> false end)
  end


  @doc """
  Inserts a single new struct in the data store.

  ## Autogenerate

  The primary key will be automatically included in `returning` if the
  field has type `:id` or `:binary_id` and no value was set by the
  developer or none was autogenerated by the adapter.
  """
  #@callback insert(repo, schema_meta, fields, on_conflict, returning, options) ::
  #                  {:ok, fields} | {:invalid, constraints} | no_return
  #  def insert(_,_,_,_,_) do
  def insert(repo, schema_meta, fields, on_conflict, returning, options) do
    ecto_dynamo_log(:debug, "INSERT::\n\trepo: #{inspect repo}")
    ecto_dynamo_log(:debug, "\tschema_meta: #{inspect schema_meta}")
    ecto_dynamo_log(:debug, "\tfields: #{inspect fields}")
    ecto_dynamo_log(:debug, "\ton_conflict: #{inspect on_conflict}")
    ecto_dynamo_log(:debug, "\treturning: #{inspect returning}")
    ecto_dynamo_log(:debug, "\toptions: #{inspect options}")

    insert_nil_field_option = Keyword.get(options, :insert_nil_fields, true)
    do_not_insert_nil_fields = insert_nil_field_option == false || Application.get_env(:ecto_adapters_dynamodb, :insert_nil_fields) == false

    {_, table} = schema_meta.source 
    model = schema_meta.schema
    fields_map = Enum.into(fields, %{})
    record = if do_not_insert_nil_fields, do: fields_map, else: build_record_map(model, fields_map)

    ecto_dynamo_log(:info, "#{inspect __MODULE__}.insert")
    ecto_dynamo_log(:info, "Table: #{inspect table}; Record: #{inspect record}")

    Dynamo.put_item(table, record) |> ExAws.request |> handle_error!(%{table: table, records: [record]})
    {:ok, []}
  end


  def insert_all(repo, schema_meta, field_list, fields, on_conflict, returning, options) do
    ecto_dynamo_log(:debug, "INSERT ALL::\n\trepo: #{inspect repo}")
    ecto_dynamo_log(:debug, "\tschema_meta: #{inspect schema_meta}")
    ecto_dynamo_log(:debug, "\tfield_list: #{inspect field_list}")
    ecto_dynamo_log(:debug, "\tfields: #{inspect fields}")
    ecto_dynamo_log(:debug, "\ton_conflict: #{inspect on_conflict}")
    ecto_dynamo_log(:debug, "\treturning: #{inspect returning}")
    ecto_dynamo_log(:debug, "\toptions: #{inspect options}")

    insert_nil_field_option = Keyword.get(options, :insert_nil_fields, true)
    do_not_insert_nil_fields = insert_nil_field_option == false || Application.get_env(:ecto_adapters_dynamodb, :insert_nil_fields) == false

    {_, table} = schema_meta.source
    model = schema_meta.schema

    prepared_fields = Enum.map(fields, fn(field_set) ->
      mapped_fields = Enum.into(field_set, %{})
      record = if do_not_insert_nil_fields, do: mapped_fields, else: build_record_map(model, mapped_fields)

      [put_request: [item: record]]
    end)

    records = Enum.map(prepared_fields, fn [put_request: [item: record]] -> record end)

    ecto_dynamo_log(:info, "#{inspect __MODULE__}.insert_all")
    ecto_dynamo_log(:info, "Table: #{inspect table}; Records: #{inspect records}")

    batch_write_attempt = Dynamo.batch_write_item(%{table => prepared_fields}) |> ExAws.request |> handle_error!(%{table: table, records: records})

    # THE FORMAT OF A SUCCESSFUL BATCH INSERT IS A MAP THAT WILL INCLUDE A MAP OF ANY UNPROCESSED ITEMS
    cond do
      # IDEALLY, THERE ARE NO UNPROCESSED ITEMS - THE MAP IS EMPTY
      batch_write_attempt["UnprocessedItems"] == %{} ->
        {length(records), nil}
      # TO DO: DEVELOP A STRATEGY FOR HANDLING UNPROCESSED ITEMS.
      # DOCS SUGGEST GATHERING THEM UP AND TRYING ANOTHER BATCH INSERT AFTER A SHORT DELAY
      batch_write_attempt["UnprocessedItems"] != %{} ->
        raise "#{inspect __MODULE__}.insert_all: Handling not yet implemented for \"UnprocessedItems\" as a non-empty map. ExAws.Dynamo.batch_write_item response: #{inspect batch_write_attempt}"
    end
  end

  defp build_record_map(model, fields_to_insert) do
    # Ecto does not convert empty strings to nil before passing them
    # to Repo.insert_all, and ExAws will remove empty strings (as well as empty lists)
    # when building the insertion query but not nil values. We don't mind the removal
    # of empty lists since those cannot be inserted to indexed fields, but we'd like to
    # catch the removal of fields with empty strings by ExAws to support our option, :remove_nil_fields,
    # so we convert these to nil.
    empty_strings_to_nil = fields_to_insert 
                         |> Enum.map(fn {field, val} -> {field, (if val == "", do: nil, else: val)} end)
                         |> Enum.into(%{})
    model.__struct__ |> Map.delete(:__meta__) |> Map.from_struct |> Map.merge(empty_strings_to_nil)
  end


  # In testing, 'filters' contained only the primary key and value 
  # TODO: handle cases of more than one tuple in 'filters'?
  def delete(repo, schema_meta, filters, options) do
    ecto_dynamo_log(:debug, "DELETE::\n\trepo: #{inspect repo}")
    ecto_dynamo_log(:debug, "\tschema_meta: #{inspect schema_meta}")
    ecto_dynamo_log(:debug, "\tfilters: #{inspect filters}")
    ecto_dynamo_log(:debug, "\toptions: #{inspect options}")

    {_, table} = schema_meta.source

    case Dynamo.delete_item(table, filters) |> ExAws.request! do
      %{} -> {:ok, []}
      error -> raise "Error deleting in DynamoDB. Error: #{inspect error}"
    end
  end


  # Again we rely on filters having the correct primary key value.
  # TODO: any aditional checks missing here?
  def update(repo, schema_meta, fields, filters, returning, opts) do
    ecto_dynamo_log(:debug, "UPDATE::\n\trepo: #{inspect repo}")
    ecto_dynamo_log(:debug, "\tschema_meta: #{inspect schema_meta}")
    ecto_dynamo_log(:debug, "\tfields: #{inspect fields}")
    ecto_dynamo_log(:debug, "\tfilters: #{inspect filters}")
    ecto_dynamo_log(:debug, "\treturning: #{inspect returning}")
    ecto_dynamo_log(:debug, "\toptions: #{inspect opts}")

    {_, table} = schema_meta.source

    # We offer the :range_key option for tables with composite primary key
    # since Ecto will not provide the range_key value needed for the query.
    # If :range_key is not provided, check if the table has a composite
    # primary key and query for all the key values
    updated_filters = case opts[:range_key] do
      nil -> 
        {:primary, key_list} = Ecto.Adapters.DynamoDB.Info.primary_key!(table)
        if (length key_list) > 1 do
          updated_opts = opts ++ [projection_expression: Enum.join(key_list, ", ")]
          filters_as_strings = for {field, val} <- filters, do: {Atom.to_string(field), {val, :==}}
          fetch_result = Ecto.Adapters.DynamoDB.Query.get_item(table, filters_as_strings, updated_opts)
          items = case fetch_result do
            %{"Items" => fetch_items} -> fetch_items
            %{"Item" => item}         -> [item]
            _                         -> []
          end

          if items == [], do: raise "__MODULE__.update error: no results found for record: #{inspect filters}"
          if (length items) > 1, do: raise "__MODULE__.update error: more than one result found for record: #{inspect filters}"
          
          for {field, key_map} <- Map.to_list(hd items) do
            [{_field_type, val}] = Map.to_list(key_map)
            {field, val}
          end
         else
          filters
         end

      range_key ->
        [range_key | filters]
    end

    update_expression = construct_update_expression(fields, opts)
    attribute_names = construct_expression_attribute_names(fields)
    attribute_values = construct_expression_attribute_values(fields, opts)

    base_options = [expression_attribute_names: attribute_names,
                    update_expression: update_expression]
    options = maybe_add_attribute_values(base_options, attribute_values)
    # 'options' might not have the key, ':expression_attribute_values', when there are only removal statements
    record = if options[:expression_attribute_values], do: [options[:expression_attribute_values] |> Enum.into(%{})], else: []

    Dynamo.update_item(table, updated_filters, options) |> ExAws.request |> handle_error!(%{table: table, records: record ++ []})
    {:ok, []}
  end


  defp extract_query_info(result), do: result |> Map.take(["Count", "ScannedCount", "LastEvaluatedKey"])


  # Used in update_all
  defp extract_update_params([], _params), do: []
  defp extract_update_params([%{expr: key_list}], params) do
    case List.keyfind(key_list, :set, 0) do
      {_, set_list} ->
        for s <- set_list do
          {field_atom, {:^, _, [idx]}} = s
          {field_atom, Enum.at(params,idx)}
        end
      _ -> error "#{inspect __MODULE__}.extract_update_params: Updates query :expr key list does not contain a :set key." 
    end
  end

  defp extract_update_params([a], _params), do: error "#{inspect __MODULE__}.extract_update_params: Updates is either missing the :expr key or does not contain a struct or map: #{inspect a}"
  defp extract_update_params(unsupported, _params), do: error "#{inspect __MODULE__}.extract_update_params: unsupported parameter construction. #{inspect unsupported}"


  # used in :update_all
  def get_key_values_dynamo_map(dynamo_map, {:primary, keys}) do
    # We assume that keys will be labled as "S" (String)
    for k <- keys, do: {String.to_atom(k), dynamo_map[k]["S"]}
  end


  defp construct_expression_attribute_names(fields) do
    for {f, _} <- fields, into: %{}, do: {"##{Atom.to_string(f)}", Atom.to_string(f)}
  end

  defp construct_expression_attribute_values(fields, opts) do
    remove_rather_than_set_to_null = opts[:remove_nil_fields] || Application.get_env(:ecto_adapters_dynamodb, :remove_nil_fields_on_update) == true

    # If the value is nil and the :remove_nil_fields option is set, 
    # we're removing this attribute, not updating it, so filter out any such fields:

    if remove_rather_than_set_to_null do
      for {k, v} <- fields, !is_nil(v), do: {k, v}
    else
      for {k, v} <- fields, do: {k, format_val(v)}
    end
  end

  defp format_val(v) when is_nil(v), do: %{"NULL" => "true"}
  defp format_val(v), do: v

  # DynamoDB throws an error if we pass in an empty list for attribute values,
  # so we have to implement this stupid little helper function to avoid hurting
  # its feelings:
  defp maybe_add_attribute_values(options, []) do
    options
  end
  defp maybe_add_attribute_values(options, attribute_values) do
    [expression_attribute_values: attribute_values] ++ options
  end

  defp construct_update_expression(fields, opts) do
    remove_rather_than_set_to_null = opts[:remove_nil_fields] || Application.get_env(:ecto_adapters_dynamodb, :remove_nil_fields_on_update) == true

    set_statement = construct_set_statement(fields, opts)
    rem_statement = case remove_rather_than_set_to_null do
                      true -> construct_remove_statement(fields)
                      _    -> nil
                    end
    case {set_statement, rem_statement} do
      {nil, nil} ->
        error "update statements with no set or remove operations are not supported"
      {_, nil} ->
        set_statement
      {nil, _} ->
        rem_statement
      _ ->
        "#{set_statement} #{rem_statement}"
    end
  end

  # fields::[{:field, val}]
  defp construct_set_statement(fields, opts) do
    remove_rather_than_set_to_null = opts[:remove_nil_fields] || Application.get_env(:ecto_adapters_dynamodb, :remove_nil_fields_on_update) == true

    set_clauses = for {key, val} <- fields, not (is_nil(val) and remove_rather_than_set_to_null) do
      key_str = Atom.to_string(key)
      "##{key_str}=:#{key_str}"
    end
    case set_clauses do
      [] ->
        nil
      _ ->
        "SET " <> Enum.join(set_clauses, ", ")
    end
  end

  defp construct_remove_statement(fields) do
    remove_clauses = for {key, val} <- fields, is_nil(val) do
      "##{Atom.to_string(key)}"
    end
    case remove_clauses do
      [] ->
        nil
      _ ->
        "REMOVE " <> Enum.join(remove_clauses, ", ")
    end
  end

  defp validate_where_clauses!(query) do
    for w <- query.wheres do
      validate_where_clause! w
    end
  end
  defp validate_where_clause!(%BooleanExpr{expr: {op, _, _}}) when op in [:==, :<, :>, :<=, :>=, :in], do: :ok
  defp validate_where_clause!(%BooleanExpr{expr: {logical_op, _, _}}) when logical_op in [:and, :or], do: :ok
  defp validate_where_clause!(%BooleanExpr{expr: {:is_nil, _, _}}), do: :ok
  defp validate_where_clause!(%BooleanExpr{expr: {:fragment, _, _}}), do: :ok
  defp validate_where_clause!(unsupported), do: error "unsupported where clause: #{inspect unsupported}"

  # We are parsing a nested, recursive structure of the general type:
  # %{:logical_op, list_of_clauses} | %{:conditional_op, field_and_value}
  defp extract_lookup_fields([], _params, lookup_fields), do: lookup_fields
  defp extract_lookup_fields([query | queries], params, lookup_fields) do
    # A logical operator tuple does not always have a parent 'expr' key.
    maybe_extract_from_expr = case query do
      %BooleanExpr{expr: expr} -> expr
      # TODO: could there be other cases?
      _                        -> query
    end

    case maybe_extract_from_expr do 
      # A logical operator points to a list of conditionals
      {op, _, [left, right]} when op in [:==, :<, :>, :<=, :>=, :in] ->
        {field, value} = get_op_clause(left, right, params)
        updated_lookup_fields = 
          case List.keyfind(lookup_fields, field, 0) do
            # we assume the most ops we can apply to one field is two, otherwise this might throw an error
            {field, {old_val, old_op}} ->
              List.keyreplace(lookup_fields, field, 0, {field, {[value, old_val], [op, old_op]}})

            _ -> [{field, {value, op}} | lookup_fields]
          end
        extract_lookup_fields(queries, params, updated_lookup_fields)

      # Logical operator expressions have more than one op clause
      # We are matching queries of the type: 'from(p in Person, where: p.email == "g@email.com" and p.first_name == "George")'
      # But not of the type: 'from(p in Person, where: [email: "g@email.com", first_name: "George"])'
      #
      # A logical operator is a member of a list
      {logical_op, _, clauses} when logical_op in [:and, :or] ->
        deeper_lookup_fields = extract_lookup_fields(clauses, params, [])
        extract_lookup_fields(queries, params, [{logical_op, deeper_lookup_fields} | lookup_fields])

      {:fragment, _, raw_expr_mixed_list} ->
        parsed_fragment = parse_raw_expr_mixed_list(raw_expr_mixed_list, params)
        extract_lookup_fields(queries, params, [parsed_fragment | lookup_fields])
        
      # We perform a post-query is_nil filter on indexed fields and have DynamoDB filter
      # for nil non-indexed fields (although post-query nil-filters on (missing) indexed 
      # attributes could only find matches when the attributes are not the range part of 
      # a queried partition key (hash part) since those would not return the sought records).
      {:is_nil, _, [arg]} ->
        {{:., _, [_, field_name]}, _, _} = arg

        # We give the nil value a string, "null", since it will be mapped as a DynamoDB attribute_expression_value
        extract_lookup_fields(queries, params, [{to_string(field_name), {"null", :is_nil}} | lookup_fields])

      _ -> extract_lookup_fields(queries, params, lookup_fields)
    end
  end

  # Specific (as opposed to generalized) parsing for Ecto :fragment - the only use for it
  # so far is 'between' which is the only way to query 'between' on an indexed field since
  # those accept only single conditions.
  #
  # Example with values as strings: [raw: "", expr: {{:., [], [{:&, [], [0]}, :person_id]}, [], []}, raw: " between ", expr: "person:a", raw: " and ", expr: "person:f", raw: ""]
  #
  # Example with values as part of the string itself: [raw: "", expr: {{:., [], [{:&, [], [0]}, :person_id]}, [], []}, raw: " between person:a and person:f"]
  #
  # Example with values in params: [raw: "", expr: {{:., [], [{:&, [], [0]}, :person_id]}, [], []}, raw: " between ", expr: {:^, [], [0]}, raw: " and ", expr: {:^, [], [1]}, raw: ""]
  #
  defp parse_raw_expr_mixed_list(raw_expr_mixed_list, params) do
    # group the expression into fields, values, and operators,
    # only supporting the example with values in params
    case raw_expr_mixed_list do
      [raw: _, expr: {{:., [], [{:&, [], [0]}, field_atom]}, [], []}, raw: between_str, expr: {:^, [], [idx1]}, raw: and_str, expr: {:^, [], [idx2]}, raw: _] ->
        if not (Regex.match?(~r/^\s*between\s*and\s*$/i, between_str <> and_str)), do:
          parse_raw_expr_mixed_list_error(raw_expr_mixed_list)
        {to_string(field_atom), {[Enum.at(params, idx1), Enum.at(params, idx2)], :between}}
        
      _ -> parse_raw_expr_mixed_list_error(raw_expr_mixed_list) 
    end
  end

  defp parse_raw_expr_mixed_list_error(raw_expr_mixed_list), do:
    raise "#{inspect __MODULE__}.parse_raw_expr_mixed_list parse error. We currently only support the Ecto fragment of the form, 'where: fragment(\"? between ? and ?\", FIELD_AS_VARIABLE, VALUE_AS_VARIABLE, VALUE_AS_VARIABLE)'. Received: #{inspect raw_expr_mixed_list}" 

  defp get_op_clause(left, right, params) do
    field = left |> get_field |> Atom.to_string
    value = get_value(right, params)
    {field, value}
  end

  defp get_field({{:., _, [{:&, _, [0]}, field]}, _, []}), do: field
  defp get_field(other_clause) do
    error "Unsupported where clause, left hand side: #{other_clause}"
  end

  defp get_value({:^, _, [idx]}, params), do: Enum.at(params, idx)
  # HANDLE .all(query) QUERIES
  defp get_value(other_clause, _params), do: other_clause

  defp error(msg) do
    raise ArgumentError, message: msg
  end

  # Decodes maps and datetime, seemingly unhandled by ExAws Dynamo decoder
  # (timestamps() corresponds with :naive_datetime)
  defp custom_decode(item, model) do    
    Enum.reduce(model.__schema__(:fields), item, fn (field, acc) ->
        field_is_nil = is_nil Map.get(item, field)
  
        case model.__schema__(:type, field) do
          _ when field_is_nil -> acc
          :utc_datetime   ->
            update_fun = fn v ->
              {:ok, dt, _offset} = DateTime.from_iso8601(v)
              dt
            end
            Map.update!(acc, field, update_fun)
          :naive_datetime -> Map.update!(acc, field, &NaiveDateTime.from_iso8601!/1)
          _               -> acc
        end 
      end)
  end

  # We found one instance where DynamoDB's error message could
  # be more instructive - when trying to set an indexed field to something
  # other than a string or number - so we're adding a more helpful message.
  # The parameter, 'params', has the type %{table: :string, records: [:map]}
  defp handle_error!(ex_aws_request_result, params) do
    case ex_aws_request_result do
      {:ok, result}   -> result
      {:error, error} ->
        # Check for inappropriate insert into indexed field
        indexed_fields = Ecto.Adapters.DynamoDB.Info.indexed_attributes(params.table)

        # Repo.insert_all can present multiple records at once
        forbidden_insert_on_indexed_field = Enum.reduce(params.records, false, fn (record, acc) -> 
           acc || Enum.any?(record, fn {field, val} ->
            [type] = ExAws.Dynamo.Encoder.encode(val) |> Map.keys
            # Ecto does not convert Empty strings to nil before passing them to Repo.update_all or
            # Repo.insert_all DynamoDB provides an instructive message during an update (forwarded by ExAws),
            # but less so for batch_write_item, so we catch the empty string as well.
            # Dynamo does not allow insertion of empty strings in any case.
            (Enum.member?(indexed_fields, to_string(field)) and not type in ["S", "N"]) || val == ""
          end)
        end)

        case forbidden_insert_on_indexed_field do
          false -> raise ExAws.Error, message: "ExAws Request Error! #{inspect error}"
          _     -> raise "The following request error could be related to attempting to insert an empty string or attempting to insert a type other than a string or number on an indexed field. Indexed fields: #{inspect indexed_fields}. Records: #{inspect params.records}.\n\nExAws Request Error! #{inspect error}" 
        end
    end    
  end

  def ecto_dynamo_log(level, message) do
    colors = Application.get_env(:ecto_adapters_dynamodb, :log_colors)
    d = DateTime.utc_now 
    formatted_message = "\n[Ecto Dynamo #{d.year}-#{d.month}-#{d.day} #{d.hour}:#{d.minute}:#{d.second} UTC] #{message}"
    log_path = Application.get_env(:ecto_adapters_dynamodb, :log_path)

    if level in Application.get_env(:ecto_adapters_dynamodb, :log_levels) do
      IO.ANSI.format([colors[level], formatted_message], true) |> IO.puts

      if Regex.match?(~r/\S/, log_path), do: log_pipe(log_path, formatted_message)
    end
  end

  def log_pipe(path, str) do
    {:ok, file} = File.open(path, [:append])
    IO.binwrite(file, str)
    File.close(file)
  end

end
