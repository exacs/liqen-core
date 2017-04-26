defmodule Core.QuestionController do
  use Core.Web, :controller
  alias Core.Question

  plug :find when action in [:update, :delete, :show]
  plug Core.Auth, %{key: :question,
                    type: "questions"} when action in [:create, :update, :delete]

  def index(conn, _params) do
    questions = Repo.all(Question)
    render(conn, "index.json", questions: questions)
  end

  def create(conn, question_params) do
    changeset = Question.changeset(%Question{}, question_params)

    case insert_question_and_tags(changeset) do
      {:ok, question} ->
        question = question
        |> Repo.preload(:question_tags)

        conn
        |> put_status(:created)
        |> put_resp_header("location", question_path(conn, :show, question))
        |> render("show.json", question: question)
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(Core.ChangesetView, "error.json", changeset: changeset)
    end
  end

  def show(conn, _) do
    question = conn.assigns[:question]
    |> Repo.preload(:question_tags)

    render(conn, "show.json", question: question)
  end

  def update(conn, question_params) do
    question = conn.assigns[:question]
    changeset = Question.changeset(question, question_params)

    case Repo.update(changeset) do
      {:ok, question} ->
        question = question
        |> Repo.preload(:question_tags)

        render(conn, "show.json", question: question)
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(Core.ChangesetView, "error.json", changeset: changeset)
    end
  end

  def delete(conn, _) do
    question = conn.assigns[:question]

    # Here we use delete! (with a bang) because we expect
    # it to always work (and if it does not, it will raise).
    Repo.delete!(question)

    send_resp(conn, :no_content, "")
  end

  defp find(conn = %Plug.Conn{params: %{"id" => id}}, _opts) do
    case Repo.get(Question, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> render(Core.ErrorView, "404.json", %{})
        |> halt()
      question ->
        conn
        |> assign(:question, question)
    end
  end

  defp insert_question_and_tags(changeset) do
    answer = Ecto.Changeset.get_field(changeset, :answer)

    Repo.transaction(fn ->
      result = Repo.insert(changeset)
      |> add_answer(answer)

      case result do
        {:error, changeset} ->
          Repo.rollback(changeset)

        {:ok, question, tags} ->
          Map.merge(question, %{tags: tags})
      end
    end)
  end

  # Add the answer to a question
  #
  # Returns a {:ok, tags} or {:error, changeset} tuple
  defp add_answer({:error, changeset}, _), do: {:error, changeset}
  defp add_answer({:ok, question}, answer) do
    answer
    |> Enum.map(fn item ->
      QuestionTag.changeset(%QuestionTag{}, %{tag_id: item["tag"],
                                              required: item["required"],
                                              question_id: question.id})
    end)
    |> Enum.reduce({:ok, []}, add_tag(question))
  end

  # Add a tag into a question
  #
  # Returns an arity-2 function that reduces a list of changesets reducing it
  # to a single {:ok, tags} or {:error, changeset} tuple
  defp add_tag(question), do: fn
    (_, {:error, changeset}) ->
      {:error, changeset}

    (changeset = %{valid?: valid}, {:ok, _, _}) when not valid ->
      {:error, changeset}

    (changeset, {:ok, tags}) ->
      case Repo.insert(changeset) do
        {:ok, tag} ->
          {:ok, [tag|tags]}

        {:error, changeset} ->
          {:error, changeset}
      end
  end
end
