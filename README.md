
moneymoney-truelayer
====================

An extension for [MoneyMoney.app](http://moneymoney-app.com) to fetch transactions from a large number of (mostly UK) Banks via [TrueLayer](https://truelayer.com/).

TrueLayer provides a common API to all of those banks. In some cases, they use official APIs or OpenBanking integrations, and in other cases, they use credential sharing, that is, you are giving them your bank login details. In every case, all transaction data flows through the TrueLayer servers, so be sure you are comfortable with this.


Requirements
------------

You need to create your own TrueLayer account, and get your own API key, which is free when using the "Develop" plan.


Installation
------------

#### 1. Copy the `TrueLayer.lua` file here into MoneyMoney's Extension folder

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

#### 2. Disable Signature Check

This needs a beta version of MoneyMoney.

  * Open MoneyMoney.app
  * Enable Beta-Updates
  * Install update
  * Go to "Extensions"-tab
  * Allow unsigned extensions


#### 3. Setup the redirect url.

This part is unfortunately quite difficult, but I hope TrueLayer will make it easier in the future.

You need to add `moneymoney-app://oauth` as a redirect URL to your "application" on TrueLayer. 
Unfortunately, the TrueLayer dashboard currently has a validation where it only allows regular
`http(s)://` urls, so you need to use the API to add the url.

  * Use the developer tools in your browser to find the dashboard authorization header used.

  * Execute this request in a terminal:

    ```
    curl 'https://clients-api.truelayer.com/clients/YOUR_CLIENT_ID' -X PATCH -H 'Origin: https://console.truelayer.com' -H 'Accept-Encoding: gzip, deflate, br' -H 'Authorization: Bearer YOUR_AUTH_TOKEN' -H 'Content-Type: application/json' -H 'Accept: application/json' --data-binary '{"redirectURIs":["moneymoney-app://oauth","https://console.truelayer.com/redirect-page"]}' --compressed
    ```

The easiest option might be to add a regular URL in the dashboard, find the request in the network tab, copy it as `cURL`, then change the data sent to include the fake redirect URL.


Add account
-----------

When adding an account in MoneyMoney, choose `TrueLayer` as the bank. It does not matter what login data you provide in MoneyMoney itself, those values are ignored. You are then guided through the TrueLayer flow in your browser, where you can choose the bank you want to connect.