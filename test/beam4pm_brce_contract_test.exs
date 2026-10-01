defmodule Beam4pm.BrceContractTest do
  @moduledoc """
  BRCE gate contract falsifiers (lane W6, v26.10.1 / RESOLUTION R4).

  beam4pm 26.10.1 transitively depends on `Ex4pm.Evidence.BRCE` (hex ex4pm
  26.10.1, pinned by ash_ex4pm 26.10.1). R4 defers gating any beam4pm
  resource, so the gate CONTRACT itself is proven directly here: a gate that
  cannot refuse carries no bits. Each test witnesses one documented path of
  `Ex4pm.Evidence.BRCE.execute/4,5` on deps/ex4pm/lib/ex4pm/evidence.ex:

  - non-map authority refuses `:authority_required` (:256-261)
  - map authority without the `:do` capability or an `:allow` match refuses
    `:authority_denied` (:240-254)
  - admission happens before any receipt exists (:228-238): refused calls
    mint zero receipts
  - admitted calls return `{:ok, %{result, pending, receipt}}` with outcome
    standing `:alive` (:270-273) and pending standing `:partial_alive` (:41)
  - the `:allow` list path admits without `:do` (:241-247)
  - a raising `fun` still produces an outcome receipt with standing
    `:blocked` (:301-305) — fun failure is receipted, not lost work
  - receipts land in `Ex4pm.Evidence.Store` via its public API `get/1` and
    `get_by_subject/1` (evidence.ex:89-99)
  """

  use ExUnit.Case, async: false

  alias Ex4pm.Evidence.{BRCE, Receipt, Store}

  setup do
    # R6: `:ex4pm`'s application normally auto-starts `Ex4pm.Evidence.Store`,
    # but test_helper.exs only boots ExUnit; start the named GenServer here if
    # no application under test has already started it.
    if is_nil(Process.whereis(Store)) do
      start_supervised!(Store)
    end

    :ok
  end

  defp unique_subject do
    "brce-contract-#{System.unique_integer([:positive])}"
  end

  test "non-map authority is refused with :authority_required and mints no receipt" do
    subject = unique_subject()

    assert {:error, %Ex4pm.Refusal{code: :authority_required} = refusal} =
             BRCE.execute(subject, :contract_probe, nil, fn -> :ok end)

    assert refusal.message == "DO requires an explicit authority map"
    assert %{operation: :contract_probe} = refusal.details

    # admission precedes Receipt.pending (evidence.ex:228-238): a refused DO
    # leaves zero receipts for the subject.
    assert [] = Store.get_by_subject(subject)
  end

  test "map authority without :do capability or :allow match refuses :authority_denied" do
    subject = unique_subject()
    authority = %{capabilities: [:read], allow: [:other_operation]}

    assert {:error, %Ex4pm.Refusal{code: :authority_denied} = refusal} =
             BRCE.execute(subject, :contract_probe, authority, fn -> :ok end)

    assert refusal.message == "authority does not admit requested DO operation"
    assert %{operation: :contract_probe, operation_text: "contract_probe"} = refusal.details

    assert [] = Store.get_by_subject(subject)
  end

  test "%{capabilities: [:do]} is admitted and returns receipted standing :alive" do
    subject = unique_subject()
    authority = %{capabilities: [:do]}

    assert {:ok, %{result: :executed, pending: pending, receipt: receipt}} =
             BRCE.execute(subject, :contract_probe, authority, fn -> :executed end)

    assert %Receipt{phase: :pending, standing: :partial_alive, subject_hash: ^subject} = pending
    assert pending.operation == :contract_probe

    assert %Receipt{
             phase: :outcome,
             standing: :alive,
             subject_hash: ^subject,
             operation: :contract_probe,
             parent_hash: parent_hash
           } = receipt

    assert parent_hash == pending.hash
    assert is_binary(receipt.hash) and receipt.hash != ""
  end

  test "authority with the operation in :allow admits without the :do capability" do
    subject = unique_subject()
    authority = %{allow: [:contract_probe]}

    assert {:ok, %{receipt: %Receipt{standing: :alive}}} =
             BRCE.execute(subject, :contract_probe, authority, fn -> :ok end)

    # string-keyed authority with the operation text in "allow" takes the same
    # admitted path (evidence.ex:241-246, operation_text/1 at :263-265).
    string_subject = unique_subject()
    string_authority = %{"allow" => ["contract_probe"]}

    assert {:ok, %{receipt: %Receipt{standing: :alive}}} =
             BRCE.execute(string_subject, :contract_probe, string_authority, fn -> :ok end)
  end

  test "a raising fun under admitted authority yields standing :blocked outcome receipt" do
    subject = unique_subject()
    authority = %{capabilities: [:do]}

    assert {:error, %{error: %RuntimeError{}, pending: pending, receipt: receipt}} =
             BRCE.execute(subject, :contract_probe, authority, fn ->
               raise RuntimeError, "probe explosion"
             end)

    assert %Receipt{phase: :pending, standing: :partial_alive} = pending

    assert %Receipt{
             phase: :outcome,
             standing: :blocked,
             subject_hash: ^subject,
             parent_hash: parent_hash
           } = receipt

    assert parent_hash == pending.hash

    # the failure map is hashed into artifact_hash (:48, :301); metadata carries
    # the typed result marker (:284) — the exception struct itself is returned
    # as :error, not folded into metadata.
    assert receipt.metadata == %{result: :exception}
    assert is_binary(receipt.artifact_hash)
  end

  test "receipts from an admitted DO are observable through the Store public API" do
    subject = unique_subject()

    assert {:ok, %{pending: pending, receipt: receipt}} =
             BRCE.execute(subject, :contract_probe, %{capabilities: [:do]}, fn -> :ok end)

    assert {:ok, ^receipt} = Store.get(receipt.hash)
    assert {:ok, ^pending} = Store.get(pending.hash)

    by_subject = Store.get_by_subject(subject)
    assert length(by_subject) == 2
    assert Enum.map(by_subject, & &1.phase) |> Enum.sort() == [:outcome, :pending]
    assert Enum.all?(by_subject, &(&1.operation == :contract_probe))
  end
end
