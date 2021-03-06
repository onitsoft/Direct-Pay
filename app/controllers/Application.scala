// TxBits - An open source Bitcoin and crypto currency exchange
// Copyright (C) 2014-2015  Viktor Stanchev & Kirk Zathey
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

package controllers

import javax.inject.Inject

import play.api.mvc._
import play.api.i18n.{ I18nSupport, Lang }
import play.api.Play.current
import play.api.i18n.MessagesApi
import play.i18n.Langs
import scala.language.postfixOps
import jsmessages.JsMessagesFactory

class Application @Inject() (jsMessagesFactory: JsMessagesFactory, val messagesApi: MessagesApi) extends Controller with securesocial.core.SecureSocial with I18nSupport {

  def index = UserAwareAction { implicit request =>
    Ok(views.html.content.index(request.user.isDefined))
  }

  def account = SecuredAction { implicit request =>
    Ok(views.html.exchange.account(request.user))
  }

  def user_settings = SecuredAction { implicit request =>
    Ok(views.html.exchange.user_settings(request.user))
  }

  def users_list = SecuredAction { implicit request =>
    Ok(views.html.administrator.users_list(request.user))
  }

  def orders_list = SecuredAction { implicit request =>
    Ok(views.html.administrator.orders_list(request.user))
  }

  def history = SecuredAction { implicit request =>
    Ok(views.html.exchange.history(request.user))
  }

  def deposit = SecuredAction { implicit request =>
    Ok(views.html.exchange.deposit(request.user))
  }

  def ccrypto = SecuredAction { implicit request =>
    Ok(views.html.exchange.ccrypto(request.user))
  }

  def send = SecuredAction { implicit request =>
    Ok(views.html.exchange.send(request.user))
  }

  def receive = SecuredAction { implicit request =>
    Ok(views.html.exchange.receive(request.user))
  }

  def cfiat = SecuredAction { implicit request =>
    Ok(views.html.exchange.cfiat(request.user))
  }

  def withdraw = SecuredAction { implicit request =>
    Ok(views.html.exchange.withdraw(request.user))
  }

  def automatic = SecuredAction { implicit request =>
    Ok(views.html.exchange.automatic(request.user))
  }

  def wallet = SecuredAction { implicit request =>
    Ok(views.html.exchange.dashboard(request.user))
  }

  def chlang(lang: String) = UserAwareAction { implicit request =>
    if (request.user.isDefined) {
      globals.userModel.changeLanguage(request.user.get.id, lang)
    }
    Redirect(request.headers.get("referer").getOrElse("/")).withLang(Lang.get(lang).getOrElse(Lang.defaultLang))
  }

  val messages = jsMessagesFactory.all

  val jsMessages = Action { implicit request =>
    Ok(messages(Some("window.Messages")))
  }
}