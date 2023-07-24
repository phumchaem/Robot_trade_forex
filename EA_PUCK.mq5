#property copyright "Copyright 2023, PUCKBot"
#property version "1.00"
// Import inputal class
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- introduce predefined variables for code readability
#define Ask SymbolInfoDouble(_Symbol, SYMBOL_ASK)
#define Bid SymbolInfoDouble(_Symbol, SYMBOL_BID)

enum ENUM_OPEN_STRATEGY
{
    NONE,
    JAMES,
    PUCK01,
    PUCK02,
    PUCK03,
};

enum ENUM_CLOSE_STRATEGY
{
    NONE,
    FIXCO,
    PUCK01,
    PUCK02,
    PUCK03,
};

//-- input parameters
input group "Gereral Settings";
input int magicNumber = 123456; // Magic Number
input group "Money Settings";
input bool isVolume_Percent = true; // Allow Volume Percent
input double InpRisk = 50;          // Risk Percentage of Balance (%)
input group "Trading Settings";
input double startLot = 0.01;   // Lots
input double SLPips = 3.5;      // Stoploss (in Pips)
input double TPPips = 0;        // TP (in Pips) (0 = No TP)
input int InpMax_slippage = 3;  // Maximum slippage allow_Pips.
input double InpMax_spread = 5; // Maximum allowed spread (in Point) (0 = floating)

input int maxTotalOrdersOpen = 5;
input int orderTimeLimit = 10;
input ENUM_OPEN_STRATEGY defuatOpenStrategy = ENUM_OPEN_STRATEGY::PUCK03;
input ENUM_CLOSE_STRATEGY defuatCloseStrategy = ENUM_CLOSE_STRATEGY::PUCK03;

input group "Strategy Settings";
input bool JAMES_Strategy = false;
input bool PUCK01_Strategy = false;
input bool PUCK02_Strategy = false;
input bool PUCK03_Strategy = true;

input group "JAMES Settings";
input int ConditionADXofTrend = 20;

input group "FIXCO Settings";
input double fixcoLoss = 0;             // Stoploss (in USD) (0 = No SL)
input int fixcoTimeLimitOnProfit = 5;   // Time Limit on Profit (in Minutes)
input int fixcoTimeLimitOnLoss = 60;    // Time Limit on Profit (in Minutes) (0 = No Time Limit)
input bool enableStochD1OnLoss = false; // Enable Stochastic D1 on Loss

input group "PUCK02 Settings";
input double stepMartingale = 200; // Step Martingale (in pipe) (0 = No Martingale)
input double maxMartingale = 3;    // Maximum Martingale (0 = No Martingale)
input double multiplier = 2;       // Multiplier (0 = No Martingale)
//--- indicator buffer
double iMA200Buffer[];
double iMA100Buffer[];
double iMA50Buffer[];
double iADXBuffer[];
double DI_PlusBuffer[];
double DI_MinusBuffer[];
double iStochasticBuffer[];
double iStochastic_D1_Buffer[];
double iRSIBuffer[];
double iMACDBuffer[];
double iMACD_M15_Buffer[];
double iMACDSignalBuffer[];
double iOsMABuffer[];

int handle_EMA200;
int handle_EMA100;
int handle_EMA50;
int handle_ADX;
int handle_DI_Pluse;
int handle_DI_Minus;
int handle_Stochastic;
int handle_Stochastic_D1;
int handle_RSI;
int handle_MACD;
int handle_MACD_M15;
int handle_OsMA;
//- account management
double accountBalance = 0;
double accountEquity = 0;
double accountTotalProfit = 0;
double totalProfitBySymbol = 0;

//-- order management
int totalOrdersOpen = 0;
int totalOrdersOpenBuy = 0;
int totalOrdersOpenSell = 0;
int totalOrdersOpenBySymbol = 0;
int totalOrdersOpenBuyBySymbol = 0;
int totalOrdersOpenSellBySymbol = 0;

double nextLoss = 0;
double startLotCal = 0;

bool isTradeAllowed = false;
double lotSize = 0;
double maxLotBySymbol = 0;
bool isCloseAll = false;
CPositionInfo m_position; // trade position object
CTrade m_trade;           // trading object
CSymbolInfo m_symbol;     // symbol info object
CAccountInfo m_account;   // account info wrapper
COrderInfo m_order;       // pending orders object

// int Pips2Points;    // slippage  3 pips    3=points    30=points
// double Pips2Double; // Stoploss 15 pips    0.015      0.0150
int slippage;

enum ENUM_STRATEGY
{
    NONE,
    OPENBUY,
    OPENSELL,
    OPEN,
    CLOSE,
    CLOSEBUY,
    CLOSESELL
};
int OnInit()
{
    // 3 or 5 digits detection
    // Pip and point
    if (_Digits % 2 == 1)
    {
        // Pips2Double = _Point * 10;
        // Pips2Points = 10;
        slippage = 10 * InpMax_slippage;
    }
    else
    {
        // Pips2Double = _Point;
        // Pips2Points = 1;
        slippage = InpMax_slippage;
    }
    if (!m_symbol.Name(Symbol())) // sets symbol name
        return (INIT_FAILED);

    RefreshRates();
    //--- reset error code
    ResetLastError();
    OnInitCallIndicators();
    //---
    m_trade.SetExpertMagicNumber(magicNumber);
    m_trade.SetMarginMode();
    m_trade.SetTypeFillingBySymbol(m_symbol.Name());
    m_trade.SetDeviationInPoints(slippage);
    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
    Comment("");
}

void OnTick()
{
    OnTickCopyBuffers();
    // update information
    OnTickAccountInfo();
    OnTickOrderInfo();
    // strategy
    OpenOrderManagement();
    OnTickStrategyManagment();
    Comment(
        "Balance: ", accountBalance, "\n",
        "Equity: ", accountEquity, "\n",
        "TotalProfit: ", accountTotalProfit, "\n",
        "OpenBuy: ", totalOrdersOpenBuy, "\n",
        "OpenSell: ", totalOrdersOpenSell, "\n",
        "JAMES_Logic: ", EnumToString(JAMES_Logic()), "\n",
        "nextLoss: ", nextLoss, "\n");
}
void OnTickAccountInfo()
{
    accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    accountTotalProfit = AccountInfoDouble(ACCOUNT_PROFIT);
}

void OnTickOrderInfo()
{
    nextLoss = 0;
    // startLotCal = startLot;
    totalOrdersOpen = 0;
    totalOrdersOpenBuy = 0;
    totalOrdersOpenSell = 0;
    totalProfitBySymbol = 0;
    maxLotBySymbol = 0;
    totalOrdersOpenBuyBySymbol = 0;
    totalOrdersOpenSellBySymbol = 0;
    // printf("OrdersTotal: %d\n", OrdersTotal());
    int lastPositions = PositionsTotal();
    for (int i = 0; i < lastPositions; i++)
    {
        ulong ticket;
        //--- return order ticket by its position in the list
        if ((ticket = PositionGetTicket(i)) > 0)
        {
            ENUM_POSITION_TYPE type = ENUM_POSITION_TYPE(PositionGetInteger(POSITION_TYPE));

            //--- if order is opened
            if (type == POSITION_TYPE_BUY)
            {
                totalOrdersOpenBuy++;
                string positionSymbol = PositionGetString(POSITION_SYMBOL);
                if (Symbol() == positionSymbol)
                {
                    totalOrdersOpenBuyBySymbol++;
                    double profit = PositionGetDouble(POSITION_PROFIT);
                    totalProfitBySymbol += profit;
                    double lot = PositionGetDouble(POSITION_VOLUME);
                    if (lot > maxLotBySymbol)
                    {
                        maxLotBySymbol = lot;
                    }
                }
            }
            else if (type == POSITION_TYPE_SELL)
            {
                totalOrdersOpenSell++;
                string positionSymbol = PositionGetString(POSITION_SYMBOL);
                if (Symbol() == positionSymbol)
                {
                    totalOrdersOpenSellBySymbol++;
                    double profit = PositionGetDouble(POSITION_PROFIT);
                    totalProfitBySymbol += profit;
                    double lot = PositionGetDouble(POSITION_VOLUME);
                    if (lot > maxLotBySymbol)
                    {
                        maxLotBySymbol = lot;
                    }
                }
            }
        }
    }

    totalOrdersOpen = totalOrdersOpenBuy + totalOrdersOpenSell;
    totalOrdersOpenBySymbol = totalOrdersOpenBuyBySymbol + totalOrdersOpenSellBySymbol;
    // printf("totalOrdersOpen: %d\n", totalOrdersOpen);
    // printf("totalOrdersOpenBuy: %d\n", totalOrdersOpenBuy);
    // printf("totalOrdersOpenSell: %d\n", totalOrdersOpenSell);

    // calculate lot size
}
void OnInitCallIndicators()
{
    SetIndexBuffer(0, iMA200Buffer, INDICATOR_DATA);
    handle_EMA200 = iMA(Symbol(), PERIOD_CURRENT, 200, 0, MODE_EMA, PRICE_CLOSE);

    SetIndexBuffer(0, iMA100Buffer, INDICATOR_DATA);
    handle_EMA100 = iMA(Symbol(), PERIOD_CURRENT, 100, 0, MODE_EMA, PRICE_CLOSE);

    SetIndexBuffer(0, iMA50Buffer, INDICATOR_DATA);
    handle_EMA50 = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);

    SetIndexBuffer(0, iADXBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, DI_PlusBuffer, INDICATOR_DATA);
    SetIndexBuffer(2, DI_MinusBuffer, INDICATOR_DATA);
    handle_ADX = iADX(Symbol(), PERIOD_CURRENT, 13);

    SetIndexBuffer(0, iStochasticBuffer, INDICATOR_DATA);
    handle_Stochastic = iStochastic(Symbol(), PERIOD_CURRENT, 5, 3, 3, MODE_SMA, STO_LOWHIGH);

    SetIndexBuffer(0, iStochastic_D1_Buffer, INDICATOR_DATA);
    handle_Stochastic_D1 = iStochastic(Symbol(), PERIOD_D1, 5, 3, 3, MODE_SMA, STO_LOWHIGH);

    SetIndexBuffer(0, iRSIBuffer, INDICATOR_DATA);
    handle_RSI = iRSI(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE);

    SetIndexBuffer(0, iMACDBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, iMACDSignalBuffer, INDICATOR_DATA);
    handle_MACD = iMACD(Symbol(), PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);

    SetIndexBuffer(0, iMACD_M15_Buffer, INDICATOR_DATA);
    handle_MACD_M15 = iMACD(Symbol(), PERIOD_M15, 12, 26, 9, PRICE_CLOSE);

    // OsMA
    SetIndexBuffer(0, iOsMABuffer, INDICATOR_DATA);
    handle_OsMA = iOsMA(Symbol(), PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
}

void OnTickCopyBuffers()
{
    ArraySetAsSeries(iMA200Buffer, true);
    if (!CopyBuffer(handle_EMA200, 0, 0, 2, iMA200Buffer))
    {
        return;
    };

    ArraySetAsSeries(iMA100Buffer, true);
    if (!CopyBuffer(handle_EMA100, 0, 0, 2, iMA100Buffer))
    {
        return;
    };
    ArraySetAsSeries(iMA50Buffer, true);
    if (!CopyBuffer(handle_EMA50, 0, 0, 5, iMA50Buffer))
    {
        return;
    };

    ArraySetAsSeries(iADXBuffer, true);
    if (!CopyBuffer(handle_ADX, 0, 0, 4, iADXBuffer))
    {

        return;
    }

    ArraySetAsSeries(DI_PlusBuffer, true);
    if (!CopyBuffer(handle_ADX, 1, 0, 4, DI_PlusBuffer))
    {

        return;
    }

    ArraySetAsSeries(DI_MinusBuffer, true);
    if (!CopyBuffer(handle_ADX, 2, 0, 4, DI_MinusBuffer))
    {

        return;
    }

    ArraySetAsSeries(iStochasticBuffer, true);
    if (!CopyBuffer(handle_Stochastic, 0, 0, 5, iStochasticBuffer))
    {

        return;
    }

    ArraySetAsSeries(iStochastic_D1_Buffer, true);
    if (!CopyBuffer(handle_Stochastic_D1, 0, 0, 5, iStochastic_D1_Buffer))
    {

        return;
    }

    ArraySetAsSeries(iRSIBuffer, true);
    if (!CopyBuffer(handle_RSI, 0, 0, 4, iRSIBuffer))
    {

        return;
    }

    ArraySetAsSeries(iMACDBuffer, true);
    if (!CopyBuffer(handle_MACD, 0, 0, 4, iMACDBuffer))
    {
        return;
    }

    ArraySetAsSeries(iMACD_M15_Buffer, true);
    if (!CopyBuffer(handle_MACD_M15, 0, 0, 4, iMACD_M15_Buffer))
    {
        return;
    }

    ArraySetAsSeries(iMACDSignalBuffer, true);
    if (!CopyBuffer(handle_MACD, 1, 0, 4, iMACDSignalBuffer))
    {
        return;
    }

    ArraySetAsSeries(iOsMABuffer, true);
    if (!CopyBuffer(handle_OsMA, 0, 0, 4, iOsMABuffer))
    {
        return;
    }
}
void OnTickStrategyManagment()
{

    if (!canOpenOrder())
    {
        return;
    }

    // JAMES_Strategy
    if (JAMES_Strategy == true)
    {
        ENUM_STRATEGY type = JAMES_Logic();
        if (type == OPENBUY)
        {
            string comment = "JAMES_FIXCO";
            openOrder(ORDER_TYPE_BUY, 0, comment);
        }
        else if (type == OPENSELL)
        {
            string comment = "JAMES_FIXCO";
            openOrder(ORDER_TYPE_SELL, 0, comment);
        }
    }

    if (PUCK01_Strategy == true)
    {
        ENUM_STRATEGY type = PUCK01_Logic();
        if (type == OPENBUY)
        {
            string comment = "PUCK01_PUCK01";
            openOrder(ORDER_TYPE_BUY, 0, comment);
        }
        else if (type == OPENSELL)
        {
            string comment = "PUCK01_PUCK01";
            openOrder(ORDER_TYPE_SELL, 0, comment);
        }
    }

    if (PUCK02_Strategy == true)
    {
        ENUM_STRATEGY type = PUCK02_Logic();
        if (type == OPENBUY)
        {
            string comment = "PUCK02_PUCK02";
            startLotCal = CalculateVolume();
            openOrder(ORDER_TYPE_BUY, startLotCal, comment);
        }
        else if (type == OPENSELL)
        {
            string comment = "PUCK02_PUCK02";
            startLotCal = CalculateVolume();
            openOrder(ORDER_TYPE_SELL, startLot, comment);
        }
    }
    return;
}

void OpenOrderManagement()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket;
        if ((ticket = PositionGetTicket(i)) > 0)
        {
            long _magicNumber = PositionGetInteger(POSITION_MAGIC);
            if (magicNumber != _magicNumber)
            {
                continue;
            }
            string comment_to_split = PositionGetString(POSITION_COMMENT);
            string sep = "_"; // A separator as a character
            ushort u_sep;     // The code of the separator character
            string result[];
            //--- Get the separator code
            u_sep = StringGetCharacter(sep, 0);
            //--- Split the string to substrings
            int k = StringSplit(comment_to_split, u_sep, result);
            if (k > 0)
            {
                // OPEN
                string openText = result[0];
                // printf("openText: %s", openText);
                // close
                string closeText = result[1];
                // printf("closeText: %s", closeText);

                string operationClose = EnumToString(defuatCloseStrategy);
                if (closeText != "")
                {
                    operationClose = closeText;
                }
                if (!isCloseAll)
                {
                    closeOrderLogic(ticket, operationClose);
                }
            }
        }
    }
    isCloseAll = false;
}

void closeOrderLogic(ulong ticket, string operationClose)
{
    bool isClose = false;
    ENUM_POSITION_TYPE type = ENUM_POSITION_TYPE(PositionGetInteger(POSITION_TYPE));
    // Logic for close order
    if (EnumToString(FIXCO) == operationClose)
    {
        if (FIXCO_Logic(ticket) == CLOSE)
        {
            isClose = true;
        }

        if (FIXCO_Logic(ticket) == CLOSESELL && type == POSITION_TYPE_SELL)
        {
            isClose = true;
        }

        if (FIXCO_Logic(ticket) == CLOSEBUY && type == POSITION_TYPE_BUY)
        {
            isClose = true;
        }
    }

    if (EnumToString(ENUM_CLOSE_STRATEGY::PUCK01) == operationClose)
    {
        if (PUCK01_Logic(ticket) == CLOSE)
        {
            isClose = true;
        }

        if (PUCK01_Logic(ticket) == CLOSESELL && type == POSITION_TYPE_SELL)
        {
            isClose = true;
        }

        if (PUCK01_Logic(ticket) == CLOSEBUY && type == POSITION_TYPE_BUY)
        {
            isClose = true;
        }
    }

    if (EnumToString(ENUM_CLOSE_STRATEGY::PUCK02) == operationClose)
    {
        ENUM_STRATEGY typeLogic = PUCK02_Logic(ticket);
        if (typeLogic == OPENBUY && type == POSITION_TYPE_BUY)
        {
            string comment = "PUCK02_PUCK02";
            openOrder(ORDER_TYPE_BUY, maxLotBySymbol * multiplier, comment);
        }
        else if (typeLogic == OPENSELL && type == POSITION_TYPE_SELL)
        {
            string comment = "PUCK02_PUCK02";
            openOrder(ORDER_TYPE_SELL, maxLotBySymbol * multiplier, comment);
        }
        else if (typeLogic == OPEN && type == POSITION_TYPE_SELL)
        {
            string comment = "PUCK02_PUCK02";
            openOrder(ORDER_TYPE_SELL, maxLotBySymbol * multiplier, comment);
        }
        else if (typeLogic == OPEN && type == POSITION_TYPE_BUY)
        {
            string comment = "PUCK02_PUCK02";
            openOrder(ORDER_TYPE_BUY, maxLotBySymbol * multiplier, comment);
        }
        if (typeLogic == CLOSE)
        {
            closeAllBySymbol(Symbol());
            isCloseAll = true;
            return;
        }
    }

    if (isClose)
    {
        closeOrder(ticket);
    }
}
bool canOpenOrder()
{
    if (totalOrdersOpen > maxTotalOrdersOpen)
    {
        return false;
    }
    return true;
}

bool closeOrder(ulong ticket)
{
    CTrade trade;
    ResetLastError();

    if (!PositionSelectByTicket(ticket))
    {
        Print("*! Can't find ticket: ", ticket);
        return false;
    }
    else
    {
        if (trade.PositionClose(ticket))
        {
            string message = "Symbol() " + " - Close ---> Order";
            return true;
        }
        else
        {
            Print(GetLastError());
        }

        return false;
    }
}

void openOrder(ENUM_ORDER_TYPE OrderType, double volume = 0, string comment = "")
{
    double current_bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    double current_ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double lotSizeVolume = CalculateVolume();
    if (volume > 0)
    {
        lotSizeVolume = NormalizeDouble(volume, 2);
    }
    MqlTradeRequest request = {};
    request.action = TRADE_ACTION_DEAL; // setting a pending order
    request.magic = magicNumber;        // ORDER_MAGIC
    request.symbol = Symbol();          // symbol
    request.volume = lotSizeVolume;     // volume in 0.1 lots
    request.sl = 0;                     // Stop Loss is not specified
    request.tp = 0;                     // Take Profit is not specified
    request.comment = comment;          // comment
    //--- form the order type
    request.type = OrderType; // order type
    //--- form the price for the pending order
    request.price = OrderType == ORDER_TYPE_BUY ? current_ask : current_bid;
    // request.price=OrderType == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID ;  // open price
    //--- send a trade request
    MqlTradeResult result = {};
    if (!OrderSend(request, result))
    {
        Print("OrderSend error ", GetLastError());
        return;
    }

    // string message = " ---- " + OrderType + " ---- " + Symbol() + " - Open ---> Order";
    // LineNotify(message);
}

datetime GetLastOrderOpenTime()
{
    int lastPositions = PositionsTotal();
    // printf("lastPositions: %d", lastPositions);
    if (lastPositions == 0)
    {
        return 0;
    }
    ulong ticket = PositionGetTicket(lastPositions - 1);
    datetime lastOrderOpenTime = (datetime)PositionGetInteger(POSITION_TIME);
    // printf("lastOrderOpenTime: %d", lastOrderOpenTime);
    // printf("Now: %d", lastOrderOpenTime);
    return lastOrderOpenTime;
}

bool isOrderTimeLimit()
{
    datetime lastOrderOpenTime = GetLastOrderOpenTime();
    if (lastOrderOpenTime == 0)
    {
        return false;
    }
    datetime nowDatetime = TimeCurrent();

    int timeDiff = (int)(nowDatetime - lastOrderOpenTime) / 60;

    if (timeDiff >= orderTimeLimit)
    {
        return false;
    }
    return true;
}

double CalculateVolume()
{

    double LotSize = 0;

    if (isVolume_Percent == false)
    {
        LotSize = startLot;
    }
    else
    {
        LotSize = (InpRisk)*m_account.FreeMargin();
        LotSize = LotSize / 100000;
        double n = MathFloor(LotSize / startLot);
        // Comment((string)n);
        LotSize = n * startLot;

        if (LotSize < startLot)
            LotSize = startLot;

        if (LotSize > m_symbol.LotsMax())
            LotSize = m_symbol.LotsMax();

        if (LotSize < m_symbol.LotsMin())
            LotSize = m_symbol.LotsMin();
    }

    //---
    return (LotSize);
}
//+------------------------------------------------------------------+
//| Strategy function                                          |
//+------------------------------------------------------------------+
ENUM_STRATEGY JAMES_Logic()
{
    double yellow = NormalizeDouble(iADXBuffer[0], 2);
    double green = NormalizeDouble(DI_PlusBuffer[0], 2);
    double red = NormalizeDouble(DI_MinusBuffer[0], 2);
    double ema = iMA200Buffer[0];

    double MACD_main_0 = iMACDBuffer[0];
    double MACD_main_1 = iMACDBuffer[1];
    double MACD_main_2 = iMACDBuffer[2];

    double MACD_main_M15_0 = iMACD_M15_Buffer[0];
    double MACD_main_M15_1 = iMACD_M15_Buffer[1];

    double RSI_0 = iRSIBuffer[0];
    double RSI_1 = iRSIBuffer[1];
    double RSI_2 = iRSIBuffer[2];

    double OsMA_0 = iOsMABuffer[0];
    double OsMA_1 = iOsMABuffer[1];
    double OsMA_2 = iOsMABuffer[2];

    double Stochastic_D1_0 = iStochastic_D1_Buffer[0];
    double Stochastic_D1_1 = iStochastic_D1_Buffer[1];

    double current_bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    double current_ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    datetime lastOrderOpenTime = GetLastOrderOpenTime();
    if (lastOrderOpenTime == 0)
    {
        lastOrderOpenTime = TimeCurrent();
    }
    datetime nowDatetime = TimeCurrent();

    int timeDiff = (int)(nowDatetime - lastOrderOpenTime) / 60;

    bool canOpenOrder = (GetLastOrderOpenTime() == 0 || timeDiff >= 15);
    // printf("nowDatetime: %d", nowDatetime);
    // printf("GetLastOrderOpenTime(): %d", GetLastOrderOpenTime());
    // printf("timeDiff: %d", timeDiff);
    // printf("canOpenOrder: %d", canOpenOrder);
    // Comment(
    //     "yellow: ", yellow, "\n",
    //     "green: ", green, "\n",
    //     "red: ", red, "\n",
    //     "ema: ", ema, "\n",
    //     "nowDatetime: ", nowDatetime, "\n",
    //     "GetLastOrderOpenTime == 0: ", GetLastOrderOpenTime() == 0, "\n",
    //     "GetLastOrderOpenTime: ", GetLastOrderOpenTime(), "\n",
    //     "timeDiff: ", timeDiff, "\n",
    //     "canOpenOrder: ", canOpenOrder, "\n");

    if (iADXBuffer[0] >= 25 && iADXBuffer[0] <= 35)
    {
        if (iStochasticBuffer[0] > 80 && Stochastic_D1_0 < Stochastic_D1_1)
        {
            if (DI_MinusBuffer[0] > ConditionADXofTrend)
            {

                if ((DI_MinusBuffer[0] - DI_MinusBuffer[1]) > 0 && (DI_MinusBuffer[0] - DI_MinusBuffer[1]) < 5)
                {
                    // MACD_main_0 > MACD_main_1
                    if (MACD_main_0 < MACD_main_1 || OsMA_0 < 0)
                    {
                        // if ((RSI_0 > 30 && RSI_0 < 50) || RSI_0 > 70)
                        // {
                        if (canOpenOrder)
                        {
                            return ENUM_STRATEGY::OPENSELL;
                        }
                        // }
                    }
                }
            }
        }
        else if (iStochasticBuffer[0] < 20 && Stochastic_D1_0 > Stochastic_D1_1)
        {
            if (DI_PlusBuffer[0] > ConditionADXofTrend)
            {

                if ((DI_PlusBuffer[0] - DI_PlusBuffer[1]) > 0 && (DI_PlusBuffer[0] - DI_PlusBuffer[1]) < 5)
                {

                    // MACD_main_0 > MACD_main_1
                    if (MACD_main_0 > MACD_main_1 || OsMA_0 > 0)
                    {
                        // if ((RSI_0 < 70 && RSI_0 > 50) || RSI_0 < 30)
                        // {

                        if (canOpenOrder)
                        {
                            return ENUM_STRATEGY::OPENBUY;
                        }
                        // }
                    }
                }
            }
        }
    }
    return ENUM_STRATEGY::NONE;
}

ENUM_STRATEGY FIXCO_Logic(ulong ticket)
{
    if (PositionSelectByTicket(ticket) == true)
    {
        double Stochastic_D1_0 = iStochastic_D1_Buffer[0];
        double Stochastic_D1_1 = iStochastic_D1_Buffer[1];
        double orderLotVolume = (double)PositionGetDouble(POSITION_VOLUME);
        double profitMin = (orderLotVolume * 100) * 0.3;
        double profitMax = (orderLotVolume * 100) * 0.5;
        datetime orderDate = (datetime)PositionGetInteger(POSITION_TIME);
        datetime nowDatetime = TimeCurrent();
        int timeDiff = (int)(nowDatetime - orderDate) / 60;

        if (PositionGetString(POSITION_SYMBOL) == Symbol() && PositionGetDouble(POSITION_PROFIT) > profitMin)
        {

            if (timeDiff > fixcoTimeLimitOnProfit)
            {

                return ENUM_STRATEGY::CLOSE;
            }
            
            else
            {
                if (PositionGetDouble(POSITION_PROFIT) > profitMax)
                {
                    return ENUM_STRATEGY::CLOSE;
                }
            }
        }
        else if (PositionGetString(POSITION_SYMBOL) == Symbol() && PositionGetDouble(POSITION_PROFIT) < -fixcoLoss)
        {
      
            if (timeDiff > fixcoTimeLimitOnLoss && fixcoLoss != 0)
            {
                if (enableStochD1OnLoss)
                {
                    if (Stochastic_D1_0 < Stochastic_D1_1)
                    {
                        return ENUM_STRATEGY::CLOSESELL;
                    }

                    if (Stochastic_D1_0 > Stochastic_D1_1)
                    {
                        return ENUM_STRATEGY::CLOSEBUY;
                    }
                }
                else
                {
                    return ENUM_STRATEGY::CLOSE;
                }
            }
        }
    }
    return ENUM_STRATEGY::NONE;
}

ENUM_STRATEGY PUCK01_Logic(ulong ticket = 0)
{
    double MACD_main_0 = iMACDBuffer[0];
    double MACD_main_1 = iMACDBuffer[1];
    double MACD_main_2 = iMACDBuffer[2];
    double MACD_signal_0 = iMACDSignalBuffer[0];
    double MACD_signal_1 = iMACDSignalBuffer[1];
    double MACD_signal_2 = iMACDSignalBuffer[2];
    double ADX_0 = iADXBuffer[0];
    double ADX_1 = iADXBuffer[1];
    double ADX_2 = iADXBuffer[2];
    double ADX_DI_Plus_0 = DI_PlusBuffer[0];
    double ADX_DI_Plus_1 = DI_PlusBuffer[1];
    double ADX_DI_Plus_2 = DI_PlusBuffer[2];
    // DI_MinusBuffer
    double ADX_DI_Minus_0 = DI_MinusBuffer[0];
    double ADX_DI_Minus_1 = DI_MinusBuffer[1];
    double ADX_DI_Minus_2 = DI_MinusBuffer[2];
    // iStochasticBuffer[0]
    double Stochastic_0 = iStochasticBuffer[0];
    double Stochastic_1 = iStochasticBuffer[1];
    double Stochastic_2 = iStochasticBuffer[2];
    double Stochastic_3 = iStochasticBuffer[3];
    double Stochastic_4 = iStochasticBuffer[4];

    // EMAs
    double EMA200_0 = iMA200Buffer[0];
    double EMA100_0 = iMA100Buffer[0];
    double EMA50_0 = iMA50Buffer[0];
    double EMA50_1 = iMA50Buffer[1];
    double EMA50_2 = iMA50Buffer[2];

    double current_bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    double current_ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

    // Buy Condition
    // 0. EMA50_0 > EMA100_0 && EMA100_0 > EMA200_0 && current_bid > EMA200_0 && current_ask > EMA200_0
    if (current_ask > EMA50_0 && current_bid > EMA50_0)
    {
        printf("Buy: 0. EMA 50 > 100 > 200");
        // 1. ADX 0 1 > 20
        if (ADX_0 > 20 && ADX_1 > 20)
        {
            printf("Buy: 1. ADX 0 1 > 20");
            // 2. ADX_DI_Plus_0 > ADX_DI_Minus_0 && ADX_DI_Plus_0 > ADX_DI_Plus_1
            if (ADX_DI_Plus_0 > ADX_DI_Minus_0 && ADX_DI_Plus_0 > ADX_DI_Plus_1)
            {
                printf("Buy: 2. ADX_DI_Plus_0 > ADX_DI_Minus_0 && ADX_DI_Plus_0 > ADX_DI_Plus_1 > ADX_DI_Plus_2");
                // 3. (Stochastic 0 or 1 or 2 or 3 or 4 < 20) and Stochastic 0 > 1
                if ((Stochastic_0 < 20 || Stochastic_1 < 20 || Stochastic_2 < 20) && Stochastic_0 > Stochastic_1)
                {
                    printf("Buy: 3. (Stochastic 0 or 1 or 2 or 3 or 4 < 20) and Stochastic 0 > 1");
                    // 4. MACD_main 0 1 2 > 0 and MACD_main 0 < 1 < 2
                    if (MACD_main_0 < 0 && MACD_main_1 < 0 && MACD_main_2 < 0 && MACD_main_0 > MACD_main_1 && MACD_main_1 > MACD_main_2)
                    {
                        printf("Buy: 4. MACD_main 0 1 2 > 0 and MACD_main 0 < 1 < 2");
                        // 5.  MACD_signal_0 < MACD_main_0 and MACD_signal 0 > 1 > 2
                        if (MACD_signal_0 < MACD_main_0 && MACD_signal_0 > MACD_signal_1 && MACD_signal_1 > MACD_signal_2)
                        {
                            printf("Buy: 5.  MACD_signal_0 < MACD_main_0 and MACD_signal 0 > 1 > 2");
                            // OPEN Buy Condition
                            // isOrderTimeLimit
                            if (!isOrderTimeLimit())
                            {
                                return ENUM_STRATEGY::OPENBUY;
                            }
                        }
                    }
                }
            }
        }
    }
    // OPEN Sell Condition
    // 0. EMA50_0 < EMA100_0 && EMA100_0 < EMA200_0 && current_bid < EMA200_0 && current_ask < EMA200_0
    if (current_ask < EMA50_0 && current_bid < EMA50_0)
    {
        printf("Sell: 0. EMA 50 < 100 < 200");
        // 1. ADX 0 > 1 > 2 and ADX_0 > 20
        if (ADX_0 > 20 && ADX_1 > 20)
        {
            printf("Sell: 1. ADX 0 > 1 > 2 and ADX_0 > 20");
            // 2. ADX_DI_Plus_0 < ADX_DI_Minus_0 && ADX_DI_Minus_0 > ADX_DI_Minus_1
            if (ADX_DI_Plus_0 < ADX_DI_Minus_0 && ADX_DI_Minus_0 > ADX_DI_Minus_1)
            {
                printf("Sell: 2. ADX_DI_Plus_0 < ADX_DI_Minus_0 && ADX_DI_Minus_0 > ADX_DI_Minus_1 > ADX_DI_Minus_2");
                // 3. (Stochastic 0 or 1 or 2 or 3 or 4 > 80) and Stochastic 0 < 1
                if ((Stochastic_0 > 80 || Stochastic_1 > 80 || Stochastic_2 > 80) && Stochastic_0 < Stochastic_1)
                {
                    printf("Sell: 3. (Stochastic 0 or 1 or 2 or 3 or 4 > 80) and Stochastic 0 < 1");
                    // 4. MACD_main 0 1 2 < 0 and MACD_main 0 > 1 > 2
                    if (MACD_main_0 > 0 && MACD_main_1 > 0 && MACD_main_2 > 0 && MACD_main_0 < MACD_main_1 && MACD_main_1 < MACD_main_2)
                    {
                        printf("Sell: 4. MACD_main 0 1 2 < 0 and MACD_main 0 > 1 > 2");
                        // 5.  MACD_signal_0 > MACD_main_0 and MACD_signal 0 < 1 < 2
                        if (MACD_signal_0 > MACD_main_0 && MACD_signal_0 < MACD_signal_1 && MACD_signal_1 < MACD_signal_2)
                        {
                            printf("Sell: 5.  MACD_signal_0 > MACD_main_0 and MACD_signal 0 < 1 < 2");
                            // OPEN Sell Condition
                            if (!isOrderTimeLimit())
                            {
                                return ENUM_STRATEGY::OPENSELL;
                            }
                        }
                    }
                }
            }
        }
    }
    if (ticket != 0)
    {
        if (PositionSelectByTicket(ticket) == true)
        {
            double orderLotVolume = (double)PositionGetDouble(POSITION_VOLUME);
            double profitMin = (orderLotVolume * 100) * 0.3;
            double profitMax = (orderLotVolume * 100) * 0.5;
            datetime orderDate = (datetime)PositionGetInteger(POSITION_TIME);
            datetime nowDatetime = TimeCurrent();
            int timeDiff = (int)(nowDatetime - orderDate) / 60;

            if (PositionGetString(POSITION_SYMBOL) == Symbol() && PositionGetDouble(POSITION_PROFIT) > profitMin)
            {

                // if (timeDiff > fixcoTimeLimitOnProfit)
                // {

                //     return ENUM_STRATEGY::CLOSE;
                // }
                // else
                // {
                //     if (PositionGetDouble(POSITION_PROFIT) > fixcoProfit2)
                //     {
                //         return ENUM_STRATEGY::CLOSE;
                //     }
                // }

                // Close Buy Condition
                // EMA50_0 < EMA100_0 && EMA100_0 < EMA200_0 && current_bid < EMA200_0 && current_ask < EMA200_0
                if (current_ask < EMA50_0 && current_bid < EMA50_0 && current_ask < EMA50_1 && current_bid < EMA50_1 && current_ask < EMA50_2 && current_bid < EMA50_2)
                {
                    return ENUM_STRATEGY::CLOSEBUY;
                }

                // Close Sell Condition
                // EMA50_0 > EMA100_0 && EMA100_0 > EMA200_0 && current_bid > EMA200_0 && current_ask > EMA200_0
                if (current_ask > EMA50_0 && current_bid > EMA50_0 && current_ask > EMA50_1 && current_bid > EMA50_1 && current_ask > EMA50_2 && current_bid > EMA50_2)
                {
                    return ENUM_STRATEGY::CLOSESELL;
                }
            }
            else if (PositionGetString(POSITION_SYMBOL) == Symbol() && PositionGetDouble(POSITION_PROFIT) < -fixcoLoss)
            {
                if (timeDiff > fixcoTimeLimitOnLoss && fixcoLoss != 0)
                {

                    // Close Buy Condition
                    // EMA50_0 < EMA100_0 && EMA100_0 < EMA200_0 && current_bid < EMA200_0 && current_ask < EMA200_0
                    if (current_ask < EMA50_0 && current_bid < EMA50_0 && current_ask < EMA50_1 && current_bid < EMA50_1 && current_ask < EMA50_2 && current_bid < EMA50_2)
                    {
                        return ENUM_STRATEGY::CLOSEBUY;
                    }

                    // Close Sell Condition
                    // EMA50_0 > EMA100_0 && EMA100_0 > EMA200_0 && current_bid > EMA200_0 && current_ask > EMA200_0
                    if (current_ask > EMA50_0 && current_bid > EMA50_0 && current_ask > EMA50_1 && current_bid > EMA50_1 && current_ask > EMA50_2 && current_bid > EMA50_2)
                    {
                        return ENUM_STRATEGY::CLOSESELL;
                    }
                }
            }
        }
    }
    return ENUM_STRATEGY::NONE;
}

ENUM_STRATEGY PUCK02_Logic(ulong ticket = 0)
{
    if (ticket == 0 && totalOrdersOpenBySymbol == 0)
    {
        return JAMES_Logic();
    }
    else if (ticket != 0 && totalOrdersOpenBySymbol > 0)
    {
        if (PositionSelectByTicket(ticket) == true)
        {
            double orderLotVolume = (double)PositionGetDouble(POSITION_VOLUME);
            double profitMin = (orderLotVolume * 100) * 0.3;
            double profitMax = (orderLotVolume * 100) * 0.5;
            datetime orderDate = (datetime)PositionGetInteger(POSITION_TIME);
            datetime nowDatetime = TimeCurrent();
            int timeDiff = (int)(nowDatetime - orderDate) / 60;
            double orderProfit = totalProfitBySymbol;
            if (PositionGetString(POSITION_SYMBOL) == Symbol())
            {
                if (orderProfit > profitMin)
                {
                    if (timeDiff > fixcoTimeLimitOnProfit)
                    {

                        return ENUM_STRATEGY::CLOSE;
                    }
                    else
                    {
                        if (orderProfit > profitMax)
                        {
                            return ENUM_STRATEGY::CLOSE;
                        }
                    }
                }
                else if (orderProfit < 0)
                {
                    nextLoss = 0;
                    double nextlot = startLotCal;
                    for (int i = 1; i <= totalOrdersOpenBySymbol; i++)
                    {
                        double point = stepMartingale * (totalOrdersOpenBySymbol - (i - 1));
                        nextLoss = nextLoss + (point * nextlot);
                        nextlot = nextlot * multiplier;
                    }
                    if (nextLoss > 0 && orderProfit < -nextLoss)
                    {
                        if (totalOrdersOpenBySymbol < maxMartingale)
                        {
                            return JAMES_Logic();
                        }
                    }
                }
            }
        }
    }
    return ENUM_STRATEGY::NONE;
}
void closeAllBySymbol(string symbol = "")
{
    int i = PositionsTotal() - 1;
    while (i >= 0)
    {
        if (m_trade.PositionClose(PositionGetSymbol(i)))
            i--;
    }
}
//+------------------------------------------------------------------+
//| Strategy function                                          |
//+------------------------------------------------------------------+

bool RefreshRates(void)
{
    //--- refresh rates
    if (!m_symbol.RefreshRates())
    {
        Print("RefreshRates error");
        return (false);
    }
    //--- protection against the return value of "zero"
    if (Ask == 0 || Bid == 0)
        return (false);
    //---
    return (true);
}