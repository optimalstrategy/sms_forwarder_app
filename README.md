# SMS forwarder app
I have two phones, one primary and the other just to receive SMS messages. Carrying and using two 
phones at once is such a pain, that's why I coded this app.

## Development and building 
1. Install [flutter](https://flutter.io/docs/get-started/install)
2. Follow instructions on [this page](https://flutter.io/docs/deployment/android)

## The app supports 3 ways to forward your SMS messages:
1. Using deployed telegram bot [link].
2. Using your own telegram bot
3. Using HTTP callback

<img src="screenshots/main_screen.jpg" width="270" height="537">


## Way #1 - Deployed bot
You can forward messages using a deployed bot.
<br>I've deployed one for personal usage (but you can use it too), the default field values are its data. 
If you don't trust me (or anybody else), feel free to clone the bot repo and deploy it yourself.
<br>Here is the picture of the interface:
![](screenshots/deployed_bot.jpg)
<br>You just need to fill out the login field (and other ones in case you've deployed your own bot).

<br>Then press `Save` and open generated link in the browser or telegram app:<p>
![](screenshots/deployed_bot_url.jpg)

<br>You'll receive a confirmation from the bot, and now forwarding works!
![](screenshots/confirmation.jpg)
![](screenshots/test_msg.jpg)

The button in the main menu becomes green:
![](screenshots/deployed_bot_success.jpg)


## Way #2 - Your telegram bot
In this case you'll need a bot token + your telegram chat id. 
You can read how to get these [here](https://core.telegram.org/bots).
![](screenshots/telegram_bot.jpg)


## Way #3 - HTTP callback
The app can forward messages to your http endpoint. Simply put the callback address and press save:
![](screenshots/http_callback.jpg)


## Managing the settings
You can reset settings by pressing this little round button at the down right. 
Tapping accept will do the thing and will also turn off forwarding.
![](screenshots/reset_settings_popup.jpg)
