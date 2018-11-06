# SMS forwarder app

Forwards SMS to telegram or your HTTP endpoint.

### The app supports 3 ways to forward your SMS messages:
1. Using deployed telegram bot (link to repo)
2. Using your own telegram bot
3. Using HTTP callback

![](screenshots/main_screen.jpg)


### Way #1 - Deployed bot
You can forward messages using a deployed bot.
<br>I've deployed one for personal usage (but you can use it too), the default field values are its data. 
If you don't trust me (or anybody else), feel free to clone the bot repo and deploy it yourself.
<br>Here is the picture of the interface:
![](screenshots/deployed_bot.jpg)
You just need to fill out the login field (and other ones in case you've deployed your own bot).

<br>Then press `Save` and open generated link in the browser or telegram app:<p>
![](screenshots/deployed_bot_url.jpg)

<br>You'll receive a confirmation from bot, and now everything works!
![](screenshots/confirmation.jpg)
![](screenshots/test_msg.jpg)

The button in the main menu became green:
![](screenshots/deployed_bot_success.jpg)


### Way #2 - Your telegram bot
In this case you'll need a bot token + your telegram chat id. You can read how to get these [here](https://core.telegram.org/bots).
![](screenshots/telegram_bot.jpg)


### Way #3 - HTTP callback
The app can forward messages to your http endpoint. Simply put the address and press save:
![](screenshots/http_callback.jpg)


### Managing the settings
You can reset settings by pressing on this little round bound at the down right. 
Tapping accept will do the thing and will also turn off forwarding.
![](screenshots/reset_settings_popup.jpg)
