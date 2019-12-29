-- Amazon Plugin for https://moneymoney-app.com
--
-- Copyright 2019 Michael Beutling

-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
-- (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify,
-- merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
-- OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
-- BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
-- OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

local connection=nil
local secPassword
local secUsername
local captcha1run
local mfa1run
local aName
local html

local config={
  str2date = {
    Januar=1,
    Februar=2,
    ["März"]=3,
    April=4,
    Mai=5,
    Juni=6,
    Juli=7,
    August=8,
    September=9,
    Oktober=10,
    November=11,
    Dezember=12
  },
  domain='.amazon.de',
  configOk=true,
  services    = {"Amazon Orders"},
  description = "Give you a overview about your amazon orders.",
  contra="Amazon contra ",
  encoding='latin9',
}

local configFileName='amazon_orders.json'
-- run every time which plug in is loaded
local configFile=io.open(configFileName,"rb")
if configFile~=nil then
  local configJson=configFile:read('*all')
  --print(configJson)
  local configTemp=JSON(configJson):dictionary()
  if configTemp['configOk'] then
    config=configTemp
    print('config read...')
  end
else
  print('write config...')
  configFile=io.open(configFileName,"wb")
  configFile:write(JSON():set(config):json())
end
io.close(configFile)
print("plugin loaded...")

local baseurl='https://www'..config['domain']

WebBanking{version  = 1.00,
  url         = baseurl,
  services    = config['services'],
  description = config['description']}


function connectShop(method, url, postContent, postContentType, headers)
  return HTML(connectShopRaw(method, url, postContent, postContentType, headers))
end

function connectShopRaw(method, url, postContent, postContentType, headers)
  if url:lower():sub(1,4) ~= "http" then
    url=baseurl..url
  end

  -- postContentType=postContentType or "application/json"

  if headers == nil then
    headers={
      --["DNT"]="1",
      --["Upgrade-Insecure-Requests"]="1",
      --["Connection"]="close",
      --["Accept"]="text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      }
  end

  if method == 'POST' then
  end

  if connection == nil then
    connection = Connection()
    --connection.useragent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:66.0) Gecko/20100101 Firefox/66.0"

    local status,err = pcall( function()
      for i in string.gmatch(LocalStorage.cookies, '([^; ]+)') do
        if  i:sub(1, #'ap-fid=') ~= 'ap-fid=' and i:sub(-#'=deleted') ~= '=deleted' then
          -- print("keep cookie:"..i)
          connection:setCookie(i..'; Domain='..config['domain']..'; Expires=Tue, 01-Jan-2036 08:00:01 GMT; Path=/')
        else
        -- print("suppress cockie:"..i)
        end
      end
    end) --pcall
  end


  local content, charset, mimeType, filename, headers = connection:request(method, url, postContent, postContentType, headers)

  if baseurl == url:lower():sub(1,#baseurl) then
    --print("store cookies=",connection:getCookies())

    -- work around for deleted cookies, prevent captcha
    connection:setCookie('a-ogbcbff=; Domain='..config['domain']..'; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/')
    connection:setCookie('ap-fid=; Domain='..config['domain']..'; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/ap/; Secure')

    for i in string.gmatch(connection:getCookies(), '([^; ]+)') do
      if  i:sub(1, #'ap-fid=') == 'ap-fid=' or i:sub(-#'=deleted') == '=deleted' then
        error("unwanted cockie:"..i)
      end
    end
    LocalStorage.cookies=connection:getCookies()
  else
  -- print("skip cookie saving")
  end
  return content
end


function SupportsBank (protocol, bankCode)
  return protocol == ProtocolWebBanking and "Amazon Orders" == bankCode:sub(1,#"Amazon Orders")
end

function enterCredentials()
  local xpform='//*[@name="signIn"]'
  if html:xpath(xpform):attr("name") ~= '' then
    print("enter username/password")
    html:xpath('//*[@name="email"]'):attr("value", secUsername)
    html:xpath('//*[@name="password"]'):attr("value",secPassword)
    html= connectShop(html:xpath(xpform):submit())
  end
end

function InitializeSession2 (protocol, bankCode, step, credentials, interactive)
  -- Login.
  if step==1 then
    if LocalStorage.getOrders == nil then
      LocalStorage.getOrders={}
    end

    secUsername=credentials[1]
    secPassword=credentials[2]
    captcha1run=true
    mfa1run=true
    -- uncomment for forced log out
    --LocalStorage.cookies=nil
    aName=nil

    html = connectShop("GET",baseurl)
    html= connectShop(html:xpath('//a[@id="nav-orders"]'):click())

    enterCredentials()
  end

  -- Captcha
  --
  local captcha=html:xpath('//img[@id="auth-captcha-image"]'):attr('src')
  --div id="image-captcha-section"
  if captcha ~= "" then
    -- print("login captcha")
    if captcha1run then
      local pic=connectShopRaw("GET",captcha)
      captcha1run=false
      return {
        title=html:xpath('//div[@id="auth-warning-message-box"]//li'):text(),
        challenge=pic,
        label=html:xpath('//div[@id="auth-warning-message-box"]//h4'):text()
      }
    else
      html:xpath('//*[@name="guess"]'):attr("value",credentials[1])
      -- hack: make checkbox to text field
      html:xpath('//*[@name="rememberMe"]'):attr('type','text')
      html:xpath('//*[@name="rememberMe"]'):attr("value",'true')
      enterCredentials()
      captcha1run=true
    end
  end

  enterCredentials()

  -- 2.FA
  local mfatext=html:xpath('//form[@id="auth-mfa-form"]//p'):text()
  if mfatext ~= "" then
    -- print("login mfa")
    if mfa1run then
      -- print("mfa="..mfatext)
      mfa1run=false
      return {
        title='Two-factor authentication',
        challenge=mfatext,
        label='Code'
      }
    else
      html:xpath('//*[@name="otpCode"]'):attr("value",credentials[1])
      -- hack: make checkbox to text field
      html:xpath('//*[@name="rememberDevice"]'):attr('type','text')
      html:xpath('//*[@name="rememberDevice"]'):attr("value",'true')
      html= connectShop(html:xpath('//*[@id="auth-mfa-form"]'):submit())
      mfa1run=true
    end
  end
  enterCredentials()

  if html:xpath('//*[@id="timePeriodForm"]'):attr('id') == 'timePeriodForm' then
    aName=html:xpath('//span[@class="nav-line-3"]'):text()
    if aName == "" then
      aName="Unkown"
      -- print("can't get username, new layout?")
    else
    -- print("name="..aName)
    end
  else
    LocalStorage.cookies=nil
    return LoginFailed
  end

  return nil
end

function ListAccounts (knownAccounts)
  -- Return array of accounts.
  local name=aName
  if aName == nil or aName== "" then
    name=secUsername
  end
  LocalStorage.getOrders['mix']=false
  LocalStorage.getOrders['normal']=false
  LocalStorage.getOrders['inverse']=false
  return {[1]={
    name = "Amazon "..name,
    owner = secUsername,
    accountNumber="mix",
    type = AccountTypeOther
  },[2]={
    name = "Amazon "..name,
    owner = secUsername,
    accountNumber="normal",
    type = AccountTypeOther
  },[3]={
    name = "Amazon "..name,
    owner = secUsername,
    accountNumber="inverse",
    type = AccountTypeOther
  }}
end

function RefreshAccount (account, since)
  local mixed=false

  local divisor=-100
  if account.accountNumber == "inverse" then
    divisor=100
  end

  if account.accountNumber == "mix" then
    mixed=true
  end
  print("Refresh ",account.accountNumber)
  if LocalStorage.getOrders[account.accountNumber] == false or LocalStorage.getOrders[account.accountNumber] == nil then
    LocalStorage.getOrders[account.accountNumber]=true

    return {balance=0, transactions={[1]=
      {
        name="Please reload!",
        amount = 0,
        bookingDate = 1,
        purpose = "... and drink a coffee :)",
      }
    }}
  end

  html=connectShop("GET",baseurl)

  -- Bestellungen
  html= connectShop(html:xpath('//a[@id="nav-orders"]'):click())

  if LocalStorage.OrderCache == nil then
    LocalStorage.OrderCache={}
  end

  if LocalStorage.orderFilterCache == nil then
    LocalStorage.orderFilterCache={}
  end
  --LocalStorage.orderFilterCache={}

  local orders={}
  local orderFilterSelect=html:xpath('//select[@name="orderFilter"]'):children()
  orderFilterSelect:each(function(index,element)
    local orderFilterVal=element:attr('value')
    local foundOrders=true
    local foundNewOrders=false
    if LocalStorage.orderFilterCache[orderFilterVal] == nil then
      --print(orderFilterVal)
      html:xpath('//*[@name="orderFilter"]'):select(orderFilterVal)
      html=connectShop(html:xpath('//*[@id="timePeriodForm"]'):submit())
      local foundEnd=false
      repeat
        html:xpath('//a[contains(@href,"order-details")]'):each(function(index,orderLink)
          local url=orderLink:attr('href')
          local orderCode=string.match(url,'orderID=([%d-]+)')
          if orderCode ~= "" then
            if  LocalStorage.OrderCache[orderCode] == nil then
              -- print("new order="..orderCode)
              orders[orderCode]=url
              foundNewOrders=true
            end
          else
            foundOrders=false
          end
        end)
        local nextPage=html:xpath('//li[@class="a-last"]/a[@href]')
        if nextPage:text() ~= "" then
          html=connectShop(nextPage:click())
        else
          foundEnd=true
        end
      until foundEnd
      if orderFilterVal ~= 'months-6' and not foundNewOrders and foundOrders then
        LocalStorage.orderFilterCache[orderFilterVal]=true
        --print("orderFilter="..orderFilterVal.." cached")
      end
    end
    --print("new orders="..#orders)
    return true
  end)

  local posbox='//div[@class="a-row"]/div[contains(@class,"a-fixed-left-grid")]//'

  for orderCode,orderUrl in pairs(orders) do
    html=connectShop("GET",orderUrl)
    local orderDate = MM.toEncoding(config['encoding'],html:xpath('//span[@class="order-date-invoice-item"]'):text())
    --print("orderCode="..orderCode.." orderDate="..orderDate)
    if orderDate ~= "" then
      local orderDay,orderMonth,orderYear=string.match(orderDate,"(%d+)%.%s+([%wä]+)%s+(%d+)")
      local orderMonth=config['str2date'][orderMonth]
      if orderMonth ~= nil then
        local bookingDate=os.time({year=orderYear,month=orderMonth,day=orderDay})
        local orderPositions={}
        local total=0
        for k,position in pairs({html:xpath(posbox..'span[contains(@class,"price")]'),html:xpath(posbox..'div[contains(@class,"gift-card-instance")]')}) do
          position:each(function (index,element)
            local purpose=MM.toEncoding(config['encoding'],element:xpath('../..//a'):text())
            local amount=element:text()
            purpose=string.match(purpose,"^%s*(.+)%s*$")
            local amountHigh,amountLow=string.match(amount,"(%d+)[,%.](%d%d)")
            amount=amountHigh*100+amountLow
            --print(purpose,amount)
            table.insert(orderPositions,{purpose=purpose,amount=amount})
            total=total+amount
            return true
          end)
        end
        if #orderPositions >0 then
          LocalStorage.OrderCache[orderCode]={total=total,since=since,bookingDate=bookingDate,orderPositions=orderPositions}
          --print("store="..orderCode)
        end

      else
        error("date error, order="..orderCode)
      end
    end

  end

  local transactions={}
  local balance=0
  --since=0
  for orderCode,order in pairs(LocalStorage.OrderCache) do
    balance=balance+order.total
    if order.since >= since then
      for index,position in pairs(order.orderPositions) do
        table.insert(transactions,{
          name=orderCode,
          amount = position.amount/divisor,
          bookingDate = order.bookingDate,
          purpose = position.purpose
        })
      end
      if mixed then
        table.insert(transactions,{
          name=orderCode,
          amount = order.total/divisor*-1,
          bookingDate = order.bookingDate,
          purpose = config['contra']..orderCode,
        })
      end
    end
  end

  if mixed then
    balance=0
  end

  -- Return balance and array of transactions.
  return {balance=balance/divisor, transactions=transactions}
end

function EndSession ()
-- Logout.
-- print("logout, not really :)")
end

