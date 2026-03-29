# frozen_string_literal: true

class KnowledgeDocumentsController < ApplicationController
  before_action :require_authentication

  def create_from_text
    doc = current_user.account.knowledge_documents.new
    doc.body_text = permitted_text[:body_text].to_s
    doc.title = permitted_text[:title].presence
    doc.title ||= "Заметка #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}"

    if doc.save
      IndexKnowledgeDocumentJob.perform_later(doc.id)
      redirect_to redirect_path_for_text, notice: "Текст принят. Индексация в базе знаний запущена."
    else
      redirect_to redirect_path_for_text, alert: doc.errors.full_messages.join(", ")
    end
  end

  def create
    doc = current_user.account.knowledge_documents.new
    doc.file.attach(permitted[:file])
    doc.title = permitted[:title].presence || doc.file&.filename&.to_s

    if doc.save
      IndexKnowledgeDocumentJob.perform_later(doc.id)
      redirect_to redirect_path, notice: "Файл принят. Индексация в базе знаний запущена."
    else
      redirect_to redirect_path, alert: doc.errors.full_messages.join(", ")
    end
  end

  def destroy
    doc = current_user.account.knowledge_documents.find(params[:id])
    doc.destroy!
    redirect_to redirect_path, notice: "Документ удалён из базы знаний."
  end

  private

  def permitted
    params.permit(:file, :title, :lead_id, :tab)
  end

  def permitted_text
    params.permit(:body_text, :title, :lead_id, :tab)
  end

  def redirect_path
    lid = permitted[:lead_id].presence || params[:lead_id].presence
    tab = permitted[:tab].presence_in(%w[leads rag]) || params[:tab].presence_in(%w[leads rag])
    q = {}
    q[:lead_id] = lid if lid.present?
    q[:tab] = tab if tab.present?
    root_path(q)
  end

  def redirect_path_for_text
    lid = permitted_text[:lead_id].presence || params[:lead_id].presence
    tab = permitted_text[:tab].presence_in(%w[leads rag]) || params[:tab].presence_in(%w[leads rag])
    q = {}
    q[:lead_id] = lid if lid.present?
    q[:tab] = tab if tab.present?
    root_path(q)
  end
end
