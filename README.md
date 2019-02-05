
moneymoney-truelayer
====================

An extension for [MoneyMoney.app](http://moneymoney-app.com) to fetch transactions from a large number of (mostly UK) Banks via [TrueLayer](https://truelayer.com/).

TrueLayer provides a common API to all of those banks. In some cases, they use official APIs or OpenBanking integrations, and in other cases, they use credential sharing, that is, you are giving them your bank login details. In every case, all transaction data flows through the TrueLayer servers, so be sure you are comfortable with this.


Requirements
------------

You need to create your own TrueLayer account, and get your own API key, which is free when using the "Develop" plan.


Installation
------------

#### 1. Be sure to install the beta version of MoneyMoney.

Download the beta version from [moneymoney-app.com/beta/](https://moneymoney-app.com/beta/).


#### 2. Copy the `TrueLayer.lua` file here into MoneyMoney's Extension folder

  * Open MoneyMoney.app
  * Tap "Hilfe", "Show Database in Finder"
  * Copy `TrueLayer.lua` into the `Extensions` folder.
  * Edit the file and find the following two lines at the beginning of the file:

    ```
    local API_CLIENT_ID = ""
    local API_SECRET = ""
    ```

    Insert your `client_id` and `client_secret`, which you can find in your TrueLayer dashboard.
    It might look like this:

    ```
    local API_CLIENT_ID = "foobar-ru12"
    local API_SECRET = "daf37850-f3a8-4d49-9b48-3b7fb23f2f74"
    ```

#### 3. Disable Signature Check

This needs a beta version of MoneyMoney.

  * Open MoneyMoney.app
  * Enable Beta-Updates
  * Install update
  * Go to "Extensions"-tab
  * Allow unsigned extensions


#### 4. Setup the redirect url.

You need to add `https://service.moneymoney-app.com/1/redirect` as a redirect URL to your "application" on TrueLayer. 


Add account
-----------

When adding an account in MoneyMoney, choose `TrueLayer` as the bank. It does not matter what login data you provide in MoneyMoney itself, those values are ignored. You are then guided through the TrueLayer flow in your browser, where you can choose the bank you want to connect.