//+------------------------------------------------------------------+
//|                                       TradingOperationsSimple.mqh |
//|                                    Copyright 2023, TradingRobots |
//|                                             https://www.example.com |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Класс торговых операций для упрощенного Trend Change            |
//+------------------------------------------------------------------+
class CTradingOperationsSimple
{
private:
    string            m_symbol;              // Торговый символ
    int               m_magicNumber;         // Магический номер
    bool              m_debugMode;           // Режим отладки
    CTrade*           m_trade;               // Указатель на объект торговли
    
public:
    // Конструктор
    CTradingOperationsSimple(string symbol, int magicNumber, CTrade* tradeObject, bool debugMode = false);
    
    // Основные торговые операции
    bool              Buy(double lotSize, double stopLoss = 0, double takeProfit = 0);
    bool              Sell(double lotSize, double stopLoss = 0, double takeProfit = 0);
    bool              ClosePosition(ulong ticket);
    void              CloseAllPositions();
    bool              ModifyStopLoss(ulong ticket, double stopLoss);
    
    // Вспомогательные функции
    bool              HasOpenPosition();
    ulong             GetCurrentPositionTicket();
    ENUM_POSITION_TYPE GetCurrentPositionType();
    double            GetCurrentPositionOpenPrice();
    double            GetCurrentPositionLots();
    double            GetCurrentPositionProfit();
    int               CountPositions();
    
    // Информация о последней сделке
    bool              GetLastTradeResult(double &profit);
    int               GetLastTradeResult(); // Упрощенная версия: 1=прибыль, -1=убыток, 0=неизвестно
    int               GetLastTradeReason(); // Получение причины закрытия: DEAL_REASON_SL, DEAL_REASON_TP и т.д.
};

//+------------------------------------------------------------------+
//| Конструктор класса                                               |
//+------------------------------------------------------------------+
CTradingOperationsSimple::CTradingOperationsSimple(string symbol, int magicNumber, CTrade* tradeObject, bool debugMode = false)
{
    m_symbol = symbol;
    m_magicNumber = magicNumber;
    m_trade = tradeObject;
    m_debugMode = debugMode;
}

//+------------------------------------------------------------------+
//| Функция открытия позиции на покупку                              |
//+------------------------------------------------------------------+
bool CTradingOperationsSimple::Buy(double lotSize, double stopLoss = 0, double takeProfit = 0)
{
    double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
    
    if(m_debugMode)
    {
        Print("DEBUG: Opening BUY position. Lot: ", lotSize, ", Symbol: ", m_symbol, 
              ", Ask: ", ask, ", SL: ", stopLoss, ", TP: ", takeProfit);
    }
    
    if(m_trade.Buy(lotSize, m_symbol, 0, stopLoss, takeProfit))
    {
        ulong ticket = m_trade.ResultOrder();
        
        if(m_debugMode)
        {
            Print("DEBUG: BUY position opened successfully. Ticket: ", ticket);
        }
        
        return true;
    }
    else
    {
        if(m_debugMode)
        {
            Print("DEBUG: Failed to open BUY position. Error: ", GetLastError());
        }
        
        return false;
    }
}

//+------------------------------------------------------------------+
//| Функция открытия позиции на продажу                              |
//+------------------------------------------------------------------+
bool CTradingOperationsSimple::Sell(double lotSize, double stopLoss = 0, double takeProfit = 0)
{
    double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    
    if(m_debugMode)
    {
        Print("DEBUG: Opening SELL position. Lot: ", lotSize, ", Symbol: ", m_symbol, 
              ", Bid: ", bid, ", SL: ", stopLoss, ", TP: ", takeProfit);
    }
    
    if(m_trade.Sell(lotSize, m_symbol, 0, stopLoss, takeProfit))
    {
        ulong ticket = m_trade.ResultOrder();
        
        if(m_debugMode)
        {
            Print("DEBUG: SELL position opened successfully. Ticket: ", ticket);
        }
        
        return true;
    }
    else
    {
        if(m_debugMode)
        {
            Print("DEBUG: Failed to open SELL position. Error: ", GetLastError());
        }
        
        return false;
    }
}

//+------------------------------------------------------------------+
//| Функция закрытия позиции по тикету                              |
//+------------------------------------------------------------------+
bool CTradingOperationsSimple::ClosePosition(ulong ticket)
{
    if(m_debugMode)
    {
        Print("DEBUG: Closing position #", ticket);
    }
    
    if(m_trade.PositionClose(ticket))
    {
        if(m_debugMode)
        {
            Print("DEBUG: Position #", ticket, " closed successfully");
        }
        return true;
    }
    else
    {
        if(m_debugMode)
        {
            Print("DEBUG: Failed to close position #", ticket, ". Error: ", GetLastError());
        }
        return false;
    }
}

//+------------------------------------------------------------------+
//| Функция закрытия всех позиций                                    |
//+------------------------------------------------------------------+
void CTradingOperationsSimple::CloseAllPositions()
{
    int count = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
           PositionGetInteger(POSITION_MAGIC) == m_magicNumber)
        {
            if(ClosePosition(ticket))
            {
                count++;
            }
        }
    }
    
    if(m_debugMode)
    {
        Print("DEBUG: Closed ", count, " positions");
    }
}

//+------------------------------------------------------------------+
//| Функция модификации стоп-лосса позиции                           |
//+------------------------------------------------------------------+
bool CTradingOperationsSimple::ModifyStopLoss(ulong ticket, double stopLoss)
{
    if(!PositionSelectByTicket(ticket))
    {
        if(m_debugMode)
        {
            Print("DEBUG: Position #", ticket, " does not exist");
        }
        return false;
    }
    
    double currentStopLoss = PositionGetDouble(POSITION_SL);
    double currentTakeProfit = PositionGetDouble(POSITION_TP);
    
    if(currentStopLoss == stopLoss)
    {
        return true; // Уже установлен на нужном уровне
    }
    
    if(m_debugMode)
    {
        Print("DEBUG: Modifying stop loss for position #", ticket, 
              ". Current SL: ", currentStopLoss, ", New SL: ", stopLoss);
    }
    
    if(m_trade.PositionModify(ticket, stopLoss, currentTakeProfit))
    {
        if(m_debugMode)
        {
            Print("DEBUG: Stop loss modified successfully for position #", ticket);
        }
        return true;
    }
    else
    {
        return false;
    }
}

//+------------------------------------------------------------------+
//| Функция проверки наличия открытой позиции                        |
//+------------------------------------------------------------------+
bool CTradingOperationsSimple::HasOpenPosition()
{
    int totalPositions = PositionsTotal();
    
    if(m_debugMode && totalPositions > 0)
    {
        Print("DEBUG TradingOps: Total positions: ", totalPositions);
    }
    
    for(int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        string symbol = PositionGetString(POSITION_SYMBOL);
        long magic = PositionGetInteger(POSITION_MAGIC);
        
        if(m_debugMode)
        {
            Print("DEBUG TradingOps: Checking position #", ticket, 
                  " Symbol: ", symbol, 
                  " Magic: ", magic);
        }
        
        if(symbol == m_symbol && magic == m_magicNumber)
        {
            if(m_debugMode)
            {
                double volume = PositionGetDouble(POSITION_VOLUME);
                double price = PositionGetDouble(POSITION_PRICE_OPEN);
                long type = PositionGetInteger(POSITION_TYPE);
                Print("DEBUG TradingOps: Found matching position #", ticket, 
                      " Type: ", type, 
                      " Volume: ", volume, 
                      " Price: ", price);
            }
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Функция получения тикета текущей позиции                         |
//+------------------------------------------------------------------+
ulong CTradingOperationsSimple::GetCurrentPositionTicket()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
           PositionGetInteger(POSITION_MAGIC) == m_magicNumber)
        {
            return ticket;
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Функция получения типа текущей позиции                           |
//+------------------------------------------------------------------+
ENUM_POSITION_TYPE CTradingOperationsSimple::GetCurrentPositionType()
{
    ulong ticket = GetCurrentPositionTicket();
    if(ticket > 0 && PositionSelectByTicket(ticket))
    {
        long type = PositionGetInteger(POSITION_TYPE);
        if(m_debugMode)
        {
            Print("DEBUG TradingOps: Position #", ticket, " type: ", type);
        }
        return (ENUM_POSITION_TYPE)type;
    }
    return WRONG_VALUE;
}

//+------------------------------------------------------------------+
//| Функция получения цены открытия текущей позиции                  |
//+------------------------------------------------------------------+
double CTradingOperationsSimple::GetCurrentPositionOpenPrice()
{
    ulong ticket = GetCurrentPositionTicket();
    if(ticket > 0 && PositionSelectByTicket(ticket))
    {
        return PositionGetDouble(POSITION_PRICE_OPEN);
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Функция получения размера лота текущей позиции                   |
//+------------------------------------------------------------------+
double CTradingOperationsSimple::GetCurrentPositionLots()
{
    ulong ticket = GetCurrentPositionTicket();
    if(ticket > 0 && PositionSelectByTicket(ticket))
    {
        return PositionGetDouble(POSITION_VOLUME);
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Функция получения прибыли текущей позиции                        |
//+------------------------------------------------------------------+
double CTradingOperationsSimple::GetCurrentPositionProfit()
{
    ulong ticket = GetCurrentPositionTicket();
    if(ticket > 0 && PositionSelectByTicket(ticket))
    {
        return PositionGetDouble(POSITION_PROFIT);
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Функция подсчета количества позиций                              |
//+------------------------------------------------------------------+
int CTradingOperationsSimple::CountPositions()
{
    int count = 0;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
           PositionGetInteger(POSITION_MAGIC) == m_magicNumber)
        {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Функция получения причины закрытия последней сделки              |
//+------------------------------------------------------------------+
int CTradingOperationsSimple::GetLastTradeReason()
{
    // Проверяем историю сделок за последние 24 часа
    datetime from = TimeCurrent() - 24*3600; // Последние 24 часа
    datetime to = TimeCurrent();
    
    if(!HistorySelect(from, to))
    {
        if(m_debugMode)
            Print("DEBUG TradingOps: Failed to select history for reason check");
        return -1; // Ошибка
    }
    
    // Ищем последнюю сделку закрытия для нашего символа и магика
    ulong lastDealTicket = 0;
    datetime lastDealTime = 0;
    
    int totalDeals = HistoryDealsTotal();
    if(m_debugMode)
        Print("DEBUG TradingOps: Checking ", totalDeals, " deals for reason");
    
    for(int i = totalDeals - 1; i >= 0; i--)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket <= 0) continue;
        
        string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
        long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
        long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
        
        if(symbol == m_symbol &&
           magic == m_magicNumber &&
           entry == DEAL_ENTRY_OUT)
        {
            datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
            if(dealTime > lastDealTime)
            {
                lastDealTime = dealTime;
                lastDealTicket = dealTicket;
            }
        }
    }
    
    if(lastDealTicket > 0)
    {
        long reason = HistoryDealGetInteger(lastDealTicket, DEAL_REASON);
        
        if(m_debugMode)
        {
            string reasonStr = "UNKNOWN";
            if(reason == DEAL_REASON_CLIENT) reasonStr = "CLIENT";
            else if(reason == DEAL_REASON_EXPERT) reasonStr = "EXPERT";
            else if(reason == DEAL_REASON_SL) reasonStr = "SL";
            else if(reason == DEAL_REASON_TP) reasonStr = "TP";
            else if(reason == DEAL_REASON_SO) reasonStr = "SO";
            
            Print("DEBUG TradingOps: Last deal #", lastDealTicket, 
                  " closed by: ", reasonStr, " (", reason, ")");
        }
        
        return (int)reason;
    }
    
    return -1; // Не найдено
}

//+------------------------------------------------------------------+
//| Функция получения результата последней сделки                    |
//+------------------------------------------------------------------+
bool CTradingOperationsSimple::GetLastTradeResult(double &profit)
{
    profit = 0.0;
    
    // Проверяем историю сделок за последние 24 часа
    datetime from = TimeCurrent() - 24*3600; // Последние 24 часа
    datetime to = TimeCurrent();
    
    if(!HistorySelect(from, to))
    {
        if(m_debugMode)
            Print("DEBUG TradingOps: Failed to select history");
        return false;
    }
    
    // Ищем последнюю сделку закрытия для нашего символа и магика
    ulong lastDealTicket = 0;
    datetime lastDealTime = 0;
    
    int totalDeals = HistoryDealsTotal();
    if(m_debugMode)
        Print("DEBUG TradingOps: Total deals in history: ", totalDeals);
    
    for(int i = totalDeals - 1; i >= 0; i--)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket <= 0) continue;
        
        string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
        long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
        long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
        datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
        
        if(m_debugMode)
        {
            Print("DEBUG TradingOps: Checking deal #", dealTicket, 
                  " Symbol: ", symbol, 
                  " Magic: ", magic, 
                  " Entry: ", entry, 
                  " Time: ", dealTime);
        }
        
        if(symbol == m_symbol &&
           magic == m_magicNumber &&
           entry == DEAL_ENTRY_OUT)
        {
            if(dealTime > lastDealTime)
            {
                lastDealTime = dealTime;
                lastDealTicket = dealTicket;
                if(m_debugMode)
                    Print("DEBUG TradingOps: Found matching deal #", dealTicket);
            }
        }
    }
    
    if(lastDealTicket > 0)
    {
        profit = HistoryDealGetDouble(lastDealTicket, DEAL_PROFIT);
        double swap = HistoryDealGetDouble(lastDealTicket, DEAL_SWAP);
        double commission = HistoryDealGetDouble(lastDealTicket, DEAL_COMMISSION);
        long reason = HistoryDealGetInteger(lastDealTicket, DEAL_REASON);
        
        if(m_debugMode)
        {
            string reasonStr = "UNKNOWN";
            if(reason == DEAL_REASON_CLIENT) reasonStr = "CLIENT";
            else if(reason == DEAL_REASON_EXPERT) reasonStr = "EXPERT";
            else if(reason == DEAL_REASON_SL) reasonStr = "SL";
            else if(reason == DEAL_REASON_TP) reasonStr = "TP";
            else if(reason == DEAL_REASON_SO) reasonStr = "SO";
            
            Print("DEBUG TradingOps: Deal #", lastDealTicket, 
                  " Profit: ", profit, 
                  " Swap: ", swap, 
                  " Commission: ", commission, 
                  " Reason: ", reasonStr, " (", reason, ")",
                  " Total: ", profit + swap + commission);
        }
        
        return true;
    }
    else if(m_debugMode)
    {
        Print("DEBUG TradingOps: No matching deal found");
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Упрощенная функция получения результата последней сделки         |
//+------------------------------------------------------------------+
int CTradingOperationsSimple::GetLastTradeResult()
{
    double profit = 0.0;
    
    if(GetLastTradeResult(profit))
    {
        if(profit > 0.01) return 1;    // Прибыльная
        if(profit < -0.01) return -1;  // Убыточная
        return 0;                      // Безубыток
    }
    
    return 0; // Неизвестно
}
//+------------------------------------------------------------------+