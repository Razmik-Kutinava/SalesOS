# frozen_string_literal: true

class SessionsController < ApplicationController
  layout "application"

  def new
    redirect_to root_path if current_user
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    if user&.authenticate(params[:password].to_s)
      session[:user_id] = user.id
      redirect_to root_path, notice: "Добро пожаловать."
    else
      flash.now[:alert] = "Неверный email или пароль."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session.delete(:user_id)
    redirect_to login_path, notice: "Вы вышли."
  end
end
