% rolling calculation of aggregate model
% addpath C:\gurobi702\win64\matlab;
% warning( 'off', 'MATLAB:lang:badlyScopedReturnValue' );
RollNum=52;         %%滚动次数
RollStart=(1:24*7:8737)';       %%滚动周期起始时间
Iter=zeros(RollNum,1);        %%迭代次数
%% full period input data
load('aggregate_input_data.mat');
%%------------------------ initialization ---------------------------------
Tfull   = in.T;
TDfull  = in.TD;
A       = in.A;
in_full = in.area;
in_roll = in_full;
for a=1:A
    %%------------- area data
    in_roll(a).T=0;
    in_roll(a).TD=0;
%     in_roll(a).Onoff_t0=zeros(1,in_roll(a).Nunit);       %% initial status at t=0
%     in_roll(a).Pthermal_t0=zeros(1,in_roll(a).Nunit);    %% initial output at t=0
%     in_roll(a).On_t0=zeros(1,in_roll(a).Nunit);          %% length of time unit g has to be on at the beginning
%     in_roll(a).Off_t0=zeros(1,in_roll(a).Nunit);         %% length of time unit g has to be off at the beginning
    in_roll(a).Demand=[];        %% demand
    in_roll(a).Windmax=[];      %% theory output of wind power
    in_roll(a).PVmax  = [];      %% theory output of PV
    in_roll(a).Ftie0=[];          %% fixed power flow
    in_roll(a).Etie =[];          %% exchage energy each day
    in_roll(a).ReserveUp=[];      %% up reserve
    in_roll(a).ReserveDn=[];      %% down reserve
end
for a=1:A
    %%-------------- results
    out_full(a).Pwind = zeros(Tfull,1);                    %% output of wind power 
    out_full(a).Ppv   = zeros(Tfull,1);                    %% output of PV 
    out_full(a).Pagg  = zeros(Tfull,in_roll(a).Ntype);     %% output of thermal unit
    out_full(a).S     = zeros(Tfull,in_roll(a).Ntype);     %% number of on units;
    out_full(a).Y     = zeros(Tfull,in_roll(a).Ntype);     %% start up indicator
    out_full(a).Z     = zeros(Tfull,in_roll(a).Ntype);     %% shut down indicator
    out_full(a).SY    = zeros(Tfull,in_roll(a).Ntype);     %% number of startup units
    out_full(a).SZ    = zeros(Tfull,in_roll(a).Ntype);     %% number of shutdown units
    out_full(a).Ftie  = zeros(Tfull,in_roll(a).Ntie);
end
%% roll up
tic;
for roll=1:RollNum
    %%input the rth rolling period data
    tRoll = RollStart(roll):RollStart(roll+1)-1;
    for a=1:A
        in_roll(a).T=length(tRoll);
        if roll==1
%             in_area(a).S_t0=in_full(a).S_t0;       
%             in_area(a).Pagg_t0=in_full(a).Pagg_t0;   
%             in_area(a).TY_t0=in_full(a).TY_t0;         
%             in_area(a).TZ_t0=in_full(a).TZ_t0;       
        else
            in_roll(a).S_t0    = out_full(a).S(tRoll(1)-1,:);      
            in_roll(a).Pagg_t0 = out_full(a).Pagg(tRoll(1)-1,:);    
            [in_roll(a).TY_t0,in_roll(a).TZ_t0] = getTYZ_t0(out_full(a).Y,out_full(a).Z,in_roll(a).Minup,in_roll(a).Mindown);       
        end
        in_roll(a).Demand    = in_full(a).Demand(tRoll,:);        
        in_roll(a).Windmax   = in_full(a).Windmax(tRoll,:); 
        in_roll(a).PVmax     = in_full(a).PVmax(tRoll,:);  
        in_roll(a).ReserveUp = in_full(a).ReserveUp(tRoll,:);      %% up reserve
        in_roll(a).ReserveDn = in_full(a).ReserveDn(tRoll,:);      %% dowen reserve
    end

    %%solution
    out_roll=aggregate_model_centralized(in_roll,A);
    %%results
    for a=1:A
        out_full(a).Pwind(tRoll)  = out_roll(a).Pwind;    
        out_full(a).Ppv(tRoll)    = out_roll(a).Ppv;     
        out_full(a).Pagg(tRoll,:) = out_roll(a).Pagg;
        out_full(a).S(tRoll,:)    = out_roll(a).S;
        out_full(a).Y(tRoll,:)    = out_roll(a).Y;
        out_full(a).Z(tRoll,:)    = out_roll(a).Z;
        out_full(a).SY(tRoll,:)   = out_roll(a).SY;
        out_full(a).SZ(tRoll,:)   = out_roll(a).SZ;        
        out_full(a).Ftie(tRoll,:) = out_roll(a).Ftie;
    end
    roll
    toc;
end
%% save resluts
save aggregate_results.mat A Tfull TDfull in_full out_full;

