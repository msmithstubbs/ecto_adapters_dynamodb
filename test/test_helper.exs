# Load all our support files first, since we need some of them to define our helper modules

files = File.ls!("./test/support") |> Enum.filter(&(String.ends_with?(&1, [".ex", ".exs"])))

Enum.each files, fn(file) ->
  Code.require_file "support/#{file}", __DIR__
end

defmodule TestHelper do
  alias ExAws.Dynamo
  alias Ecto.Adapters.DynamoDB.TestRepo

  def setup_all() do
    IO.puts "starting test repo"
    TestRepo.start_link()

    IO.puts "deleting any leftover test tables that may exist"
    Dynamo.delete_table("test_person") |> ExAws.request
    Dynamo.delete_table("test_book_page") |> ExAws.request

    IO.puts "creating test person table"
    # Only need to define types for indexed fields:
    key_definitions = %{id: :string, email: :string}
    indexes = [%{
               index_name: "email",
               key_schema: [%{
                            attribute_name: "email",
                            key_type: "HASH",
               }],
               provisioned_throughput: %{
                 read_capacity_units: 100,
                 write_capacity_units: 100,
               },
               projection: %{projection_type: "ALL"}
    }]
    Dynamo.create_table("test_person", [id: :hash], key_definitions, 100, 100, indexes, []) |> ExAws.request!

    IO.puts "creating test book page table"
    key_definitions = %{id: :string, page_num: :number}
    Dynamo.create_table("test_book_page", [id: :hash, page_num: :range], key_definitions, 100, 100, [], []) |> ExAws.request!

    :ok
  end
end

# Skip EQC testing if we don't have it installed:
if Code.ensure_compiled?(:eqc) do
  defmodule TestGenerators do
    use EQC

    alias Ecto.Adapters.DynamoDB.TestSchema.Person

    def nonempty_str() do
      such_that s <- utf8() do
        # Ecto.Changeset.validate_required checks for all-whitespace
        # strings in addition to empty ones, hence the trimming:
        String.trim_leading(s) != ""
      end
    end

    def circle_list() do
      non_empty(list(nonempty_str()))
    end

    def person_generator() do
      person_with_id(nonempty_str())
    end

    def person_with_id(key_gen) do
      let {id, first, last, age, email, pass, circles} <-
          {key_gen, nonempty_str(), nonempty_str(), int(),
            nonempty_str(), nonempty_str(), circle_list()} do
        %Person{
          id: id,
          first_name: first,
          last_name: last,
          age: age,
          email: email,
          password: pass,
          circles: circles
        }
      end
    end
  end
else
  IO.puts "Could not find eqc module - skipping property based testing!"
end

ExUnit.start()
