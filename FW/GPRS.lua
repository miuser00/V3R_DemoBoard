--- myGPRSswitch
-- @module myGPRSswitch
-- @author miuser
-- @license MIT
-- @copyright Flowershe
-- @release 2019-05-06
require "socket"
require"pins"
require "misc"
require"nvm"
require "config"
require"update"

module(..., package.seeall)


--RunLED==0 不亮 未上电，1 常亮 已经联网运行，2 闪亮，联网中  
--RunLED使用pio2
--ONOFFLed==0 不亮 开关断，1 常亮 开关开
--ONOFFLed使用pio3

--ONOFFSwitch==0 关闭 1 代开
--ONOFFSwitch使用pio6

RunLED,ONOFFLed,ONOFFSwitch=0,0,0
PIO2,PIO3=0,0

--以下两个变量用于确认心跳已被服务端接收，方法为监听服务端包回声，如果指定时间未收到回声，且未超出重发次数则重发命令
local Heartbeat=0  --心跳确认 1 ，心跳尚未确认 0
local HeartbeatRetry=0 --重发确认次数

local IMEI="000000000000000"
local SN="0000000000000000"

local ID="0000000000"
local MM="0000000000000000"


-- 此处的IP和端口请填上你自己的socket服务器和端口
local ip, port = "box.miuser.net",7101

nvm.init("config.lua")

--回报心跳信号
function HeartBeat()
    if (ONOFFSwitch==1) then
        reportstring="005132A01"..ID..MM.."1234Air208ONOK05"
    end

    if (ONOFFSwitch==0) then
        reportstring="005232A01"..ID..MM.."1234Air208OFFOK05"
    end
    --log.info(heartstring)
    --sys.publish("pub_msg", reportstring)

    --开始发送
    Heartbeat=0
end

--回报当前状态
function ReportStatus()
    if (ONOFFSwitch==1) then
        reportstring="005132A01"..ID..MM.."1234Air208ONOK05"
    end

    if (ONOFFSwitch==0) then
        reportstring="005232A01"..ID..MM.."1234Air208OFFOK05"
    end
    log.info(heartstring)
    sys.publish("pub_msg", reportstring)

end

--心跳发送协程
sys.taskInit(function()

    while true do
        --有消息要发送
        if ((HeartbeatRetry>0) and (Heartbeat==0)) then   
            log.info(heartstring)
            sys.publish("pub_msg",reportstring)
            HeartbeatRetry=HeartbeatRetry-1
            sys.wait(5000)
        else

            --成功发送
            if (Heartbeat==1) then 
                HeartbeatRetry=10
            end             
            --尝试次数过多报错
            if (HeartbeatRetry<0) then 
                log.info("pub_msg","Sent was abort after 10 retry") 
                Heartbeat=1
                HeartbeatRetry=10
            end          
        end
        sys.wait(3000)
    end
end)



-- UDP接收协程
sys.taskInit(function()

    --检查固件更新

    update.request()
    --sys.timerLoopStart(log.info,1000,"testUpdate.version",_G.VERSION)
    
    --r 代表是否接收到字符
    --S 代表接收到的字符
    --p 按指定发送者解析到的字符   
    local r, s, p
    RunLED=2
    ONOFFLed=nvm.get("ONOFF")
    ONOFFSwitch=nvm.get("ONOFF")

    log.info("ONOFF",nvm.get("ONOFF"))

    while true do
        while not socket.isReady() do          
            sys.wait(1000) 
        end

        local c = socket.udp()
        while not c:connect(ip, port) do sys.wait(2000) end

    
        while true do
            r, s, p = c:recv(120000, "pub_msg")
            if r then
                log.info("这是收到了服务器下发的消息:", s)
                RunLED=1
                source = string.sub(s,8,9) 
                if (source=="08") then
                    log.info("消息来源为websocket")
                    --打开开关
                    local onstring="004832A08"..ID..MM.."1234Air208ON05"
                    local offstring="004932A08"..ID..MM.."1234Air208OFF05"

                    if string.find(s,onstring,1) then
                        ONOFFLed=1
                        ONOFFSwitch=1
                    end
                    --关闭开关
                    if string.find(s,offstring,1) then
                        ONOFFLed=0
                        ONOFFSwitch=0
                    end          
                    --回报服务器当前状态
                    ReportStatus()
                end
                if (source=="01") then
                    Heartbeat=1
                end

            elseif s == "pub_msg" then
                --log.info("这是收到了订阅的消息和参数显示:", s, p)
                if not c:send(p) then break end
            elseif s == "timeout" then
                log.info("pub_msg","这是等待超时发送心跳包的显示!")
                if not c:send("\0") then break end
            else
                log.info("pub_msg","这是socket连接错误的显示!")
                break
            end
            sys.wait(100)
        end
        c:close()
    end
end)

--定时心跳
sys.taskInit(function()
    while not socket.isReady() do 
        sys.wait(1000)
    end
    while true do
        HeartBeat()
        sys.wait(60000)
    end
end)

--开机首次上线心跳
sys.taskInit(function()
    while not socket.isReady() do 
        sys.wait(1000)
    end
    
    IMEI=tostring(misc.getImei())
    SN=tostring(misc.getSn())

    log.info("MyIMEI: "..IMEI)
    log.info("MySN: "..SN)

    ID=string.sub(IMEI,-10)
    MM=SN
    log.info("MyID: "..ID)
    log.info("My MM: "..MM)

    --如果尚未收到过数据包
    while (RunLED==2) do
        HeartbeatRetry=100
        HeartBeat()
        sys.wait(3000)
    end
end)


--RunlED闪烁
sys.taskInit(function()
    while true do
        if RunLED ==2 then
            PIO2 = PIO2==0 and 1 or 0
            pins.setup(pio.P0_2,PIO2)
        end
        sys.wait(200)
    end
end)


--刷新端口

sys.taskInit(function()
    while true do
        if RunLED==0 then
            pins.setup(pio.P0_2,0)
        elseif RunLED==1 then
            pins.setup(pio.P0_2,1)
        end
        
        if ONOFFLed==0 then
            pins.setup(pio.P0_3,0)
        elseif ONOFFLed==1 then
            pins.setup(pio.P0_3,1)
        end

        if ONOFFSwitch==0 then
            pins.setup(pio.P0_6,0)
        elseif ONOFFSwitch==1 then
            pins.setup(pio.P0_6,1)
        end

        sys.wait(500)
    end
end)

function gpio31IntFnc(msg)
    log.info("testGpioSingle.gpio4IntFnc",msg,getGpio31Fnc())
    --上升沿中断
    if msg==cpu.INT_GPIO_POSEDGE then
    --下降沿中断
    else
        ONOFFSwitch = ONOFFSwitch==0 and 1 or 0
        ONOFFLed=ONOFFSwitch    
        nvm.set("ONOFF",ONOFFSwitch)  
        log.info("ONOFF",nvm.get("ONOFFSwitch"))
        ReportStatus()

    end
end

--GPIO4配置为中断，可通过getGpio4Fnc()获取输入电平，产生中断时，自动执行gpio4IntFnc函数
getGpio31Fnc = pins.setup(pio.P0_31,gpio31IntFnc)