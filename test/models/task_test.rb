require "test_helper"

class TaskTest < ActiveSupport::TestCase
  test "requires title" do
    account = create_account!
    lead = create_lead!(account)
    task = Task.new(lead: lead, title: "", status: "open")
    assert_not task.valid?
    assert task.errors.key?(:title)
  end

  test "rejects invalid status" do
    account = create_account!
    lead = create_lead!(account)
    task = Task.new(lead: lead, title: "T", status: "archived")
    assert_not task.valid?
    assert task.errors.key?(:status)
  end

  test "assignee is optional" do
    account = create_account!
    lead = create_lead!(account)
    task = Task.create!(lead: lead, title: "Solo", status: "open", assignee: nil)
    assert_nil task.assignee_id
  end
end
