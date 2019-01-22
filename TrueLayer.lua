-- Extension for MoneyMoney based on TrueLayer
-- TrueLayer provides access to a number of UK banks.
--
-- Copyright (c) 2018 Michael Elsdorfer
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

--[[
TODO
* Support /cards endpoint
-- ]]


local API_CLIENT_ID = ""
local API_SECRET = ""


-------------------------


local BANK_CODE = "TrueLayer"

WebBanking {
  version = 0.1,
  url = "https://truelayer.com",
  services = {BANK_CODE},
  description = string.format(MM.localizeText("Many UK banks"), BANK_CODE),
}

-- HTTPS connection object.
local connection

-- Set to true on initial setup to query all transactions
local isInitialSetup = false

local AUTH_URL = "https://auth.truelayer.com/connect/token"
local URL = "https://api.truelayer.com/data/v1"

function SupportsBank(protocol, bankCode)
    return protocol == ProtocolWebBanking and bankCode == BANK_CODE
end


local clientId
local clientSecret


function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  connection = Connection() 

  -- MoneyMoney asks for an email, we get credentials = [email]
  -- After the browser returns from oAuth, we get credentials = [code]

  if step == 1 then
    clientId = API_CLIENT_ID
    clientSecret = API_SECRET

    -- Create HTTPS connection object.
    connection = Connection()

    -- Check if access token is still valid.
    local authenticated = false
    if LocalStorage.accessToken and os.time() < LocalStorage.expiresAt then
      print("Existing access token still valid, keep it")

      -- TODO: Do a test request
      -- local whoami = queryPrivate("ping/whoami")
      -- authenticated = whoami and whoami["authenticated"]
      authenticated = true
    else
      print("Existing access token no longer valid")
    end

    -- Obtain OAuth 2.0 authorization code from web browser.
    if not authenticated then
      local options = {}
      options["enable_mock"] = "true"
      options["enable_oauth_providers"] = "true"
      options["enable_open_banking_providers"] = "true"
      options["enable_credentials_sharing_providers"] = "true"
      options["client_id"] = MM.urlencode(clientId)
      options["nonce"] = "" .. os.time()
      options["scope"] = MM.urlencode("info accounts balance transactions cards offline_access")
      options["redirect_uri"] = "moneymoney-app://oauth"
      options["response_type"] = "code"
    
      print("Returning an oAuth request to MoneyMoney")
      return {
        title = "Truelayer API",
        challenge = "https://auth.truelayer.com/?" .. stringify(options)
        -- The URL argument "state" will be automatically inserted by MoneyMoney.
      }
    end
  end

  if step == 2 then
    local authorizationCode = credentials[1]

    -- Exchange authorization code for access token.
    print("Requesting OAuth access token with authorization code: " .. authorizationCode)
    requestAccessToken(credentials[1])

    -- Not really necessary, but allows MoneyMoney to suggest the right country in the account settings as long as Monzo has no IBAN.
    LocalStorage.country = "gb"
  end
end

function ListAccounts(knownAccounts)
  isInitialSetup = true
  local accountsResponse = queryPrivate("accounts").results
  local accounts = {}
  for key, account in pairs(accountsResponse) do
    accounts[#accounts + 1] = {
      -- String name: Bezeichnung des Kontos
      name = account.display_name,
      -- String owner: Name des Kontoinhabers
      owner = "",
      -- String accountNumber: Kontonummer
      accountNumber = account.account_number.number .. " ", -- enforces that MoneyMoney will not hide a leading zero
      -- String subAccount: Unterkontomerkmal
      subAccount = account.account_id,
      -- Boolean portfolio: true für Depots und false für alle anderen Konten
      portfolio = false,
      -- String bankCode: Bankleitzahl
      bankCode = account.account_number.sort_code,
      -- String currency: Kontowährung
      currency = account.currency,
      -- String iban: IBAN
      iban = account.account_number.iban,
      -- String bic: BIC
      bic = account.account_number.swift_bic,
      -- Konstante type: Kontoart;
      type = accountTypeForTrueLayerAccountType(account.account_type)
    }
  end
  return accounts
end


function accountTypeForTrueLayerAccountType(trueLayerAccountTypeString)
  local dict = {
    BUSINESS_TRANSACTION = AccountTypeGiro,
    BUSINESS_SAVINGS = AccountTypeSavings,
    TRANSACTION = AccountTypeGiro,
    SAVINGS = AccountTypeSavings,
  }

  return dict[trueLayerAccountTypeString] or AccountTypeOther
end


-- Refreshes the account and retrieves transactions
function RefreshAccount(account, since)  
  MM.printStatus("Refreshing account " .. account.name)

  local params = {}
  -- TrueLayer by default gives us 3 months, so: TODO: Use a higher since value
  -- if no since is given to us from MoneyMoney.
  if not isInitialSetup and not (since == nil) then    
    params["from"] = luaDateToTrueLayerDate(since)
    -- TrueLayer ignores from unless a to is also given?
    -- Add an extra day so as to not run into timezone mismatches
    params["to"] = luaDateToTrueLayerDate(os.time())
  end  

  local transactionsResponse = queryPrivate("accounts/" .. account.subAccount .. "/transactions", params)
  if nil == transactionsResponse.results then
    return transactionsResponse.error_description
  end

  local t = {} -- List of transactions to return
  for index, trueLayerTransaction in pairs(transactionsResponse.results) do
    local transaction = transactionForTrueLayerTransaction(trueLayerTransaction)
    if transaction == nil then
      print("Skipped transaction: " .. trueLayerTransaction.transaction_id)
    else
      t[#t + 1] = transaction
      print("Processed transaction: " .. trueLayerTransaction.transaction_id)
    end
  end

  local balance = queryPrivate("accounts/" .. account.subAccount .. "/balance")

  return {
    balance = balance.results[1].current,
    transactions = t
  }
end

function transactionForTrueLayerTransaction(transaction)
  t = {
    -- String name: Name des Auftraggebers/Zahlungsempfängers
    name = nameForTransaction(transaction),
    -- String accountNumber: Kontonummer oder IBAN des Auftraggebers/Zahlungsempfängers
    -- String bankCode: Bankzeitzahl oder BIC des Auftraggebers/Zahlungsempfängers
    -- Number amount: Betrag
    amount = transaction.amount,
    -- String currency: Währung
    currency = transaction.currency,
    -- Number bookingDate: Buchungstag; Die Angabe erfolgt in Form eines POSIX-Zeitstempels.
    bookingDate = apiDateStrToTimestamp(transaction.timestamp),
    -- Number valueDate: Wertstellungsdatum; Die Angabe erfolgt in Form eines POSIX-Zeitstempels.
    valueDate = apiDateStrToTimestamp(transaction.timestamp),
    -- String purpose: Verwendungszweck; Mehrere Zeilen können durch Zeilenumbrüche ("\n") getrennt werden.
    purpose = transaction.description,
    -- Number transactionCode: Geschäftsvorfallcode
    -- Number textKeyExtension: Textschlüsselergänzung
    -- String purposeCode: SEPA-Verwendungsschlüssel
    purposeCode = transaction.transaction_category,
    -- String bookingKey: SWIFT-Buchungsschlüssel
    bookingKey = transaction.transaction_id,
    -- String bookingText: Umsatzart
    --bookingText = transaction.notes,
    -- String primanotaNumber: Primanota-Nummer
    -- String customerReference: SEPA-Einreicherreferenz
    -- String endToEndReference: SEPA-Ende-zu-Ende-Referenz
    -- String mandateReference: SEPA-Mandatsreferenz
    -- String creditorId: SEPA-Gläubiger-ID
    -- String returnReason: Rückgabegrund
    --returnReason = transaction.decline_reason,
    -- Boolean booked: Gebuchter oder vorgemerkter Umsatz
    booked = true,
  }
  return t
end

function nameForTransaction(transaction)
  --- https://docs.truelayer.com/#transaction-categories
  local transactionName

  -- e.g. Barclays has provider_merchant_name and it is often better/more readable/lowercase than "merchant_name".
  if not (transaction.meta == nil) and not (transaction.meta.provider_merchant_name == nil) then
    transactionName = transaction.meta.provider_merchant_name
  -- e.g. Barclays also has merchant_name
  elseif transaction.merchant_name then
    transactionName = transaction.merchant_name
  -- e.g. MetroBank
  elseif not (transaction.meta == nil) and not (transaction.meta.transaction_type == nil) then    
    transactionName = transaction.meta.transaction_type
  -- e.g. Monzo
  elseif not (transaction.meta == nil) and not (transaction.meta.provider_transaction_category == nil) then    
    transactionName = transaction.meta.provider_transaction_category
  else
    transactionName = ""
  end
  return transactionName
end

function apiDateStrToTimestamp(dateStr)
  if string.len(dateStr) == 0 then
    return nil
  end
  local yearStr, monthStr, dayStr, hourStr, minStr, secStr = string.match(dateStr, "(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d).[0-9:+]*")
  return os.time({
    year = tonumber(yearStr),
    month = tonumber(monthStr),
    day = tonumber(dayStr),
    hour = tonumber(hourStr),
    min = tonumber(minStr),
    sec = tonumber(secStr)
  })
end

function luaDateToTrueLayerDate(date)
  -- Mind the exlamation mark which produces UTC
  local dateString = os.date("!%Y-%m-%dT%XZ", date)
  return dateString
end

function EndSession()
end


-- After an OAuth exchange, we now have to exchange the code we received against an access token
function requestAccessToken(code)  
  print("Exchanging OAuth code for an access and refresh token " .. code)
  
  local body = {}
  body["grant_type"] = "authorization_code"  
  body["redirect_uri"] = "moneymoney-app://oauth"
  body["code"] = code
  handleAuthRequest(body)
end


-- When the old acceess token has expired, TrueLayer requires us to use the refresh token to get a new one.
function refreshAccessToken()
  if LocalStorage.expiresAt and os.time() < LocalStorage.expiresAt then
    print("Current access token is still valid, not refreshing, was: " .. LocalStorage.refreshToken)
    return
  end

  print("Access token has expired, now attempting to refresh, using refresh token: " .. LocalStorage.refreshToken)

  
  local body = {}
  body["grant_type"] = "refresh_token"
  body["refresh_token"] = LocalStorage.refreshToken
  handleAuthRequest(body)
end


-- Used when setting up a token or refreshing one
function handleAuthRequest(body)
  local headers = {}  
  headers["Accept"] = "application/json"

  body["client_id"] = API_CLIENT_ID
  body["client_secret"] = API_SECRET

  local content = connection:request("POST", AUTH_URL, stringify(body), "application/x-www-form-urlencoded; charset=UTF-8", headers)

  -- The result looks like this:
  -- {
  --  "access_token": "...",
  --  "expires_in": 3600,
  --  "refresh_token": "...",
  --  "token_type": "Bearer"
  --}
  data = JSON(content):dictionary()

  if data.error then
    print(data.error, data.error_description)
    return
  end

  if data.access_token then
    LocalStorage.accessToken = data.access_token
    LocalStorage.refreshToken = data.refresh_token
    LocalStorage.expiresAt = os.time() + data["expires_in"]
  end
end

-- Builds the request for sending to TrueLayer API and unpacks
-- the returned json object into a table
function queryPrivate(method, params)
  refreshAccessToken()

  local path = string.format("/%s", method)

  if not (params == nil) then
    local queryParams = httpBuildQuery(params)
    if string.len(queryParams) > 0 then
      path = path .. "?" .. queryParams
    end
  end

  local headers = {}
  print(LocalStorage.accessToken)
  headers["Authorization"] = "Bearer " .. LocalStorage.accessToken
  headers["Accept"] = "application/json"

  print("Access token used" .. LocalStorage.accessToken)

  local content = connection:request("GET", URL .. path, nil, nil, headers)
  return JSON(content):dictionary()
end

function httpBuildQuery(params)
  local str = ''
  for key, value in pairs(params) do
    str = str .. key .. "=" .. value .. "&"
  end
  str = str.sub(str, 1, -2)
  return str
end

-- DEBUG Helpers

--[[ RecPrint(struct, [limit], [indent])   Recursively print arbitrary data.
        Set limit (default 100) to stanch infinite loops.
        Indents tables as [KEY] VALUE, nested tables as [KEY] [KEY]...[KEY] VALUE
        Set indent ("") to prefix each line:    Mytable [KEY] [KEY]...[KEY] VALUE
--]]
function RecPrint(s, l, i) -- recursive Print (structure, limit, indent)
  l = (l) or 100; i = i or ""; -- default item limit, indent string
  if (l < 1) then print "ERROR: Item limit reached."; return l - 1 end;
  local ts = type(s);
  if (ts ~= "table") then print(i, ts, s); return l - 1 end
  print(i, ts); -- print "table"
  for k, v in pairs(s) do -- print "[KEY] VALUE"
    l = RecPrint(v, l, i .. "\t[" .. tostring(k) .. "]");
    if (l < 0) then break end
  end
  return l
end


--- FROM https://github.com/luvit/lit/blob/master/deps/querystring.lua

local find = string.find
local gsub = string.gsub
local char = string.char
local byte = string.byte
local format = string.format
local match = string.match
local gmatch = string.gmatch

local function urldecode(str)
  str = gsub(str, '+', ' ')
  str = gsub(str, '%%(%x%x)', function(h)
    return char(tonumber(h, 16))
  end)
  str = gsub(str, '\r\n', '\n')
  return str
end

local function urlencode(str)
  if str then
    str = gsub(str, '\n', '\r\n')
    str = gsub(str, '([^%w])', function(c)
      return format('%%%02X', byte(c))
    end)
  end
  return str
end

local function stringifyPrimitive(v)
  return tostring(v)
end

function stringify(params, sep, eq)
  if not sep then sep = '&' end
  if not eq then eq = '=' end
  if type(params) == "table" then
    local fields = {}
    for key,value in pairs(params) do
      local keyString = stringifyPrimitive(key) .. eq
      if type(value) == "table" then
        for _, v in ipairs(value) do
          -- Removed the encode() call
          table.insert(fields, keyString .. urlencode(stringifyPrimitive(v)))
        end
      else
        -- Removed the encode() call
        table.insert(fields, keyString .. stringifyPrimitive(value))
      end
    end
    return table.concat(fields, sep)
  end
  return ''
end

-- parse querystring into table. urldecode tokens
local function parse(str, sep, eq)
  if not sep then sep = '&' end
  if not eq then eq = '=' end
  local vars = {}
  for pair in gmatch(tostring(str), '[^' .. sep .. ']+') do
    if not find(pair, eq) then
      vars[urldecode(pair)] = ''
    else
      local key, value = match(pair, '([^' .. eq .. ']*)' .. eq .. '(.*)')
      if key then
        key = urldecode(key)
        value = urldecode(value)
        local type = type(vars[key])
        if type=='nil' then
          vars[key] = value
        elseif type=='table' then
          table.insert(vars[key], value)
        else
          vars[key] = {vars[key],value}
        end
      end
    end
  end
  return vars
end