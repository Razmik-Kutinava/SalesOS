# frozen_string_literal: true

class KnowledgeQueriesController < ApplicationController
  before_action :require_authentication

  def create
    q = params.permit(:question)[:question]
    result = Knowledge::RagAnswer.call(account: current_user.account, question: q)

    status = if result.error.present? && result.answer.nil?
      :unprocessable_entity
    else
      :ok
    end

    render json: {
      answer: result.answer,
      sources: result.sources,
      grounded: result.grounded,
      error: result.error
    }, status: status
  end
end
