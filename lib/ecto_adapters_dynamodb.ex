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
    IO.puts("start_link repo: #{inspect repo} opts: #{inspect opts}")
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
    IO.puts("child spec3. REPO: #{inspect repo}\n CHILD_SPEC: #{inspect child_spec}\nOPTS: #{inspect opts}")
    child_spec
  end


  @doc """
  Ensure all applications necessary to run the adapter are started.
  """
  def ensure_all_started(repo, type) do
    IO.puts("ensure all started: type: #{inspect type} #{inspect repo}")
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
    IO.puts("PREPARE:::")
    IO.inspect(query, structs: false)
    {:nocache, query}
  end
  
  def prepare(:update_all, query) do
    IO.puts("PREPARE::UPDATE_ALL:::")
    IO.inspect(query, structs: false)
    {:nocache, query}
  end
  
  # do: {:cache, {System.unique_integer([:positive]), @conn.update_all(query)}}
  #def prepare(:delete_all, query),
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
  # TODO: What about dynamo db batch_get_item for sql 'where x in [1,2,3,4]' style queries?
  def execute(_repo, _meta, {:nocache, prepared}, params, _process = nil, opts) do
    #Logger.error "EXECUTE... EXECUTING!"
    IO.puts "EXECUTE:::"
    IO.puts "prepared: #{inspect prepared, structs: false}"
    IO.puts "params:   #{inspect params, structs: false}"
    IO.puts "opts:     #{inspect opts, structs: false}"

    {table, model} = prepared.from
    validate_where_clauses!(prepared)
    lookup_keys = extract_lookup_keys(prepared, params)
    update_params = extract_update_params(prepared.updates, params)
    key_list = Ecto.Adapters.DynamoDB.Info.primary_key!(table)

    IO.puts "table = #{inspect table}"
    IO.puts "lookup keys: #{inspect lookup_keys}"
    IO.puts "update_params: #{inspect update_params}"
    IO.puts "key_list: #{inspect key_list}"

    case prepared.updates do
      [] -> error "#{inspect __MODULE__}.execute: Updates list empty."
      _  -> 
        # Since update_all does not allow for arbitrary options, we set nil fields to Dynamo's
        # 'null' value, unless the application's environment is configured to remove the fields instead.
        remove_nil_fields = Application.get_env(:ecto_adapters_dynamodb, :remove_nil_fields_on_update_all) == true
        results_to_update = Ecto.Adapters.DynamoDB.Query.get_item(table, lookup_keys)
        IO.puts "results_to_update: #{inspect results_to_update}"

        update_all(table, key_list, results_to_update, update_params, model, [{:remove_nil_fields, remove_nil_fields} | opts])
    end

    #error "#{inspect __MODULE__}.execute is not implemented."

    #num = 0
    #rows = []
    #{num, rows}
  end


  def execute(repo, meta, {:nocache, prepared}, params, process, opts) do
    IO.puts "EXECUTE... EXECUTING!============================="
    IO.puts "REPO::: #{inspect repo, structs: false}"
    IO.puts "META::: #{inspect meta, structs: false}"
    IO.puts "PREPARED::: #{inspect prepared, structs: false}"
    IO.puts "PARAMS::: #{inspect params, structs: false}"
    IO.puts "PROCESS::: #{inspect process, structs: false}"
    IO.puts "OPTS::: #{inspect opts, structs: false}"

    {table, repo} = prepared.from
    validate_where_clauses!(prepared)
    lookup_keys = extract_lookup_keys(prepared, params)
    is_nil_clauses = extract_is_nil_clauses(prepared)

    IO.puts "table = #{inspect table}"
    IO.puts "lookup_keys = #{inspect lookup_keys}"

    result = Ecto.Adapters.DynamoDB.Query.get_item(table, lookup_keys)
    IO.puts "result = #{inspect result}"

    if result == %{} do
      # Empty map means "not found"
      {0, []}
    else
      # TODO handle queries for more than just one item? -> Yup, like Repo.get_by, which could call a secondary index.
      case result["Count"] do
        nil   -> decoded = result |> Dynamo.decode_item(as: repo) |> custom_decode(repo)
                 {1, [[decoded]]}
        # Repo.get_by only returns the head of the result list, although we could perhaps
        # support multiple wheres to filter the result list further?
        _ ->
          # HANDLE .all(query) QUERIES

          decoded = Enum.map(result["Items"], fn(item) -> 
            [Dynamo.decode_item(%{"Item" => item}, as: repo) |> custom_decode(repo)]
          end)
          filtered_decoded = handle_is_nil_clauses(decoded, is_nil_clauses)
          {length(filtered_decoded), filtered_decoded}
      end
    end
  end


  # :update_all for only one result
  defp update_all(table, key_list, %{"Item" => result_to_update}, update_params, model, opts) do
    filters = get_key_values_dynamo_map(result_to_update, key_list)
    update_expression = construct_update_expression(update_params, opts)
    attribute_names = construct_expression_attribute_names(update_params)
    attribute_values = construct_expression_attribute_values(update_params, opts)

    base_options = [expression_attribute_names: attribute_names,
                    update_expression: update_expression,
                    return_values: :all_new]
    options = maybe_add_attribute_values(base_options, attribute_values)
    result = Dynamo.update_item(table, filters, options) |> ExAws.request!

    case result do 
      %{} = update_query_result -> {1, [Dynamo.decode_item(update_query_result["Attributes"], as: model)]}
      error -> raise "#{inspect __MODULE__}.update_all, single item, error: #{inspect error}"
    end 
  end

  # :update_all for multiple results
  defp update_all(table, key_list, %{"Items" => results_to_update}, update_params, model, opts) do
    Enum.reduce results_to_update, {0, []}, fn(result_to_update, acc) ->
      filters = get_key_values_dynamo_map(result_to_update, key_list)
      update_expression = construct_update_expression(update_params, opts)
      attribute_names = construct_expression_attribute_names(update_params)
      attribute_values = construct_expression_attribute_values(update_params, opts)

      base_options = [expression_attribute_names: attribute_names,
                      update_expression: update_expression,
                      return_values: :all_new]
      options = maybe_add_attribute_values(base_options, attribute_values)

      case Dynamo.update_item(table, filters, options) |> ExAws.request! do
        %{} = update_query_result -> 
          {count, result_list} = acc
          {count + 1, [Dynamo.decode_item(update_query_result["Attributes"], as: model) | result_list]}
        error -> 
          {count, _} = acc
          raise "#{inspect __MODULE__}.update_all, multiple items. Error: #{inspect error} filters: #{inspect filters} update_expression: #{inspect update_expression} attribute_names: #{inspect attribute_names} Count: #{inspect count}" 
      end
    end
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
    IO.puts("INSERT::\n\trepo: #{inspect repo}")
    IO.puts("\tschema_meta: #{inspect schema_meta}")
    IO.puts("\tfields: #{inspect fields}")
    IO.puts("\ton_conflict: #{inspect on_conflict}")
    IO.puts("\treturning: #{inspect returning}")
    IO.puts("\toptions: #{inspect options}")

    insert_nil_field_option = List.keyfind(options, :insert_nil_fields, 0, {true, true}) |> elem(1)
    do_not_insert_nil_fields = insert_nil_field_option == false || Application.get_env(:ecto_adapters_dynamodb, :insert_nil_fields) == false

    {_, table} = schema_meta.source 
    model = schema_meta.schema
    fields_map = Enum.into(fields, %{})
    record = if do_not_insert_nil_fields, do: fields_map, else: build_record_map(model, fields_map)

    case Dynamo.put_item(table, record) |> ExAws.request |> handle_error!(%{table: table, record: record}) do
      %{} -> {:ok, []}
      _   -> raise "Exception - Ex Aws either did not return an expected result or failed to raise an error. See also #{inspect __MODULE__}.handle_error!"
    end
  end


  def insert_all(repo, schema_meta, field_list, fields, on_conflict, returning, options) do
    IO.puts("INSERT ALL::\n\trepo: #{inspect repo}")
    IO.puts("\tschema_meta: #{inspect schema_meta}")
    IO.puts("\tfield_list: #{inspect field_list}")
    IO.puts("\tfields: #{inspect fields}")
    IO.puts("\ton_conflict: #{inspect on_conflict}")
    IO.puts("\treturning: #{inspect returning}")
    IO.puts("\toptions: #{inspect options}")

    insert_nil_field_option = List.keyfind(options, :insert_nil_fields, 0, {true, true}) |> elem(1)
    do_not_insert_nil_fields = insert_nil_field_option == false || Application.get_env(:ecto_adapters_dynamodb, :insert_nil_fields) == false

    {_, table} = schema_meta.source
    model = schema_meta.schema

    prepared_fields = Enum.map(fields, fn(field_set) ->
      mapped_fields = Enum.into(field_set, %{})
      record = if do_not_insert_nil_fields, do: mapped_fields, else: build_record_map(model, mapped_fields)

      [put_request: [item: record]]
    end)

    case batch_write_attempt = Dynamo.batch_write_item([{table, prepared_fields}]) |> ExAws.request! do
      # THE FORMAT OF A SUCCESSFUL BATCH INSERT IS A MAP THAT WILL INCLUDE A MAP OF ANY UNPROCESSED ITEMS
      %{"UnprocessedItems" => %{}} ->
        cond do
          # IDEALLY, THERE ARE NO UNPROCESSED ITEMS - THE MAP IS EMPTY
          batch_write_attempt["UnprocessedItems"] == %{} ->
            {:ok, []}
          # TO DO: DEVELOP A STRATEGY FOR HANDLING UNPROCESSED ITEMS.
          # DOCS SUGGEST GATHERING THEM UP AND TRYING ANOTHER BATCH INSERT AFTER A SHORT DELAY
        end
      error -> raise "Error batch inserting into DynamoDB. Error: #{inspect error}"
    end
  end

  defp build_record_map(model, fields_to_insert) do
    model.__struct__ |> Map.delete(:__meta__) |> Map.from_struct |> Map.merge(fields_to_insert)
  end


  # In testing, 'filters' contained only the primary key and value 
  # TODO: handle cases of more than one tuple in 'filters'?
  def delete(repo, schema_meta, filters, options) do
    IO.puts("DELETE::\n\trepo: #{inspect repo}")
    IO.puts("\tschema_meta: #{inspect schema_meta}")
    IO.puts("\tfilters: #{inspect filters}")
    IO.puts("\toptions: #{inspect options}")

    {_, table} = schema_meta.source

    case Dynamo.delete_item(table, filters) |> ExAws.request! do
      %{} -> {:ok, []}
      error -> raise "Error deleting in DynamoDB. Error: #{inspect error}"
    end
  end


  # Again we rely on filters having the correct primary key value.
  # TODO: any aditional checks missing here?
  def update(repo, schema_meta, fields, filters, returning, opts) do
    IO.puts("UPDATE::\n\trepo: #{inspect repo}")
    IO.puts("\tschema_meta: #{inspect schema_meta}")
    IO.puts("\tfields: #{inspect fields}")
    IO.puts("\tfilters: #{inspect filters}")
    IO.puts("\treturning: #{inspect returning}")
    IO.puts("\toptions: #{inspect opts}")

    {_, table} = schema_meta.source
    update_expression = construct_update_expression(fields, opts)
    attribute_names = construct_expression_attribute_names(fields)
    attribute_values = construct_expression_attribute_values(fields, opts)

    base_options = [expression_attribute_names: attribute_names,
                    update_expression: update_expression]
    options = maybe_add_attribute_values(base_options, attribute_values)
 
    result = Dynamo.update_item(table, filters, options) |> ExAws.request!

    case result do
      %{} -> {:ok, []}
      error -> raise "Error updating item in DynamoDB. Error: #{inspect error}"
    end
  end

  # Used in update_all
  defp extract_update_params([], _params), do: error "#{inspect __MODULE__}.extract_update_params: Updates list is empty."
  
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
    remove_rather_than_set_to_null = List.keyfind(opts, :remove_nil_fields, 0, {false, false}) |> elem(1)

    # If the value is nil and the :remove_nil_fields option is set, 
    # we're removing this attribute, not updating it, so filter out any such fields:

    case remove_rather_than_set_to_null do
      true -> for {k, v} <- fields, !is_nil(v), do: {k, v}
      _    -> for {k, v} <- fields, do: {k, format_val(v)}
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
    remove_rather_than_set_to_null = List.keyfind(opts, :remove_nil_fields, 0, {false, false}) |> elem(1)

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
    remove_rather_than_set_to_null = List.keyfind(opts, :remove_nil_fields, 0, {false, false}) |> elem(1)

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
  defp validate_where_clause!(%BooleanExpr{expr: {:==, _, _}}), do: :ok
  defp validate_where_clause!(%BooleanExpr{expr: {:and, _, _}}), do: :ok
  defp validate_where_clause!(%BooleanExpr{expr: {:is_nil, _, _}}), do: :ok
  defp validate_where_clause!(unsupported), do: error "unsupported where clause: #{inspect unsupported}"

  defp extract_lookup_keys(query, params) do
    Enum.reduce(query.wheres, %{}, fn (where_statement, acc) ->

      case where_statement do 
        %BooleanExpr{expr: {:==, _, [left, right]}} ->
          {field, value} = get_eq_clause(left, right, params)
          Map.put(acc, field, value)

        # These :and expressions have ore than one :== clause
        %BooleanExpr{expr: {:and, _, and_group}} ->
          for clause <- and_group, into: acc do
            {:==, _, [left, right]} = clause
            get_eq_clause(left, right, params)
          end

        # These clauses can, for example, contain ":is_nil" rather than ":and" or ":=="
        # but we extract is_nil separately.
        _ -> acc
      end
    end)
  end

  defp extract_is_nil_clauses(query) do
    for %BooleanExpr{expr: {:is_nil, _, [arg]}} <- query.wheres do
      {{:., _, [_, field_name]}, _, _} = arg
      field_name
    end
  end

  defp handle_is_nil_clauses(results, is_nil_clauses) do
    IO.puts "results = #{inspect results}"
    IO.puts "is_nil_clauses = #{inspect is_nil_clauses}"
    for [r] <- results, Enum.all?(is_nil_clauses, &(matches_is_nil(r, &1))), do: [r]
  end

  defp matches_is_nil(result, is_nil_clause) do
    IO.puts "testing if is nil matches: #{inspect result} #{inspect is_nil_clause}"
    result_fields = Map.from_struct(result)
    result_fields[is_nil_clause] == nil
  end

  defp get_eq_clause(left, right, params) do
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
    IO.puts "Decoding datetime: #{inspect item}"
    Enum.reduce(model.__schema__(:fields), item, fn (field, acc) ->
        field_is_nil = is_nil Map.get(item, field)
  
        case model.__schema__(:type, field) do   
          _ when field_is_nil -> acc
          :utc_datetime   -> Map.update!(acc, field, &Ecto.DateTime.cast!/1)
          :naive_datetime -> Map.update!(acc, field, &NaiveDateTime.from_iso8601!/1)
          _               -> acc        
        end                             
      end)                              
  end

  # We found one instance where DynamoDB's error message could
  # be more instructive - when trying to set an indexed field to something
  # other than a string or number - so we're adding a more helpful message.
  defp handle_error!(ex_aws_request_result, params) do
    case ex_aws_request_result do
      {:ok, result}   -> result
      {:error, error} ->
        # Check for inappropriate insert into indexed field
        indexed_fields = Ecto.Adapters.DynamoDB.Info.indexes(params.table)
                       |> Enum.map(fn ({_, fields}) -> fields end) |> List.flatten |> Enum.uniq

        forbidden_insert_on_indexed_field = Enum.any?(params.record, fn {field, val} ->
		    [type] = ExAws.Dynamo.Encoder.encode(val) |> Map.keys
            Enum.member?(indexed_fields, to_string(field)) and not type in ["S", "N"]
          end)

        case forbidden_insert_on_indexed_field do
          false -> raise ExAws.Error, message: "ExAws Request Error! #{inspect error}"
          _     -> raise "The following request error could be related to attempting to insert a type other than a string or number on an indexed field. Indexed fields: #{inspect indexed_fields}. Record: #{inspect params.record}.\n\nExAws Request Error! #{inspect error}" 
        end
    end    
  end
end
