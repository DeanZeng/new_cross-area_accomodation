function out=aggregate_model_centralized(in,A,x0)
%    aggregate model in centralized mode
% A£º number of areas.
if nargin == 1
    A=1; UseX0 = false;
elseif nargin == 2
    UseX0 = false;
elseif nargin == 3
    UseX0 = true;
end

%% input data
T           = in.T;                 %% time horizons
% Nunit       = in.Nunit;             %% number of units
Ntype       = in.Ntype;             %% number of unit type
Ntie        = in.Ntie;              %% number of tie lines
%%------------------------ thermal unit ---------------------------------
Pmax        = in.Pmax;              %% unit maximum output        1xNtype
Pmin        = in.Pmin;              %% unit minimum output        1xNtype       
Rampup      = in.Rampup;            %% unit ramping up rates      1xNtype
Rampdown    = in.Rampdown;          %% unit ramping down rates    1xNtype
Minup       = in.Minup;             %% unit minimun up time       1xNtype
Mindown     = in.Mindown;           %% unit minimum dowm time     1xNtype
S_t0        = in.S_t0;              %% initial number being on at t=0      1xNtype
Pagg_t0     = in.Pagg_t0;           %% initial output at t=0      1xNtype
TY_t0       = in.TY_t0;             %% length of time Yg has to be 0 at the beginning       1xNtype
TZ_t0       = in.TY_t0;             %% length of time Zg has to be 0 at the beginning       1xNtype
Ng          = in.Ng;                %% number per unit type       1xNtype
% typeID      = in.typeID;            %% type ID                    1xNunit        
%%--------------------------  wind and PV ---------------------------------
Windmax     = in.Windmax;           %% theory output of wind power
PVmax       = in.PVmax;             %% theory output of PV
%%--------------------------  tie lines -----------------------------------
Tieline     = in.Tieline;           %% tie lines
Ftie0       = in.Ftie0;             %% fixed power flow
Etie        = in.Etie;              %% exchage energy each day
TDstart     = in.TDstart;
%%---------------------------- system -------------------------------------
Demand      = in.Demand;            %% demand
ReserveUp   = in.ReserveUp;         %% up reserve
ReserveDn   = in.ReserveDn;         %% dowen reserve
%%---------------------------- ADMM ---------------------------------------
% Ftie_val    = in.Ftie_val;          %% exchange information of tie line power flow 
% lamda       = in.lamda;             %% multiplers
% Rho         = in.Rho;               %% coefficient of quadratic term
%% variable
%%--------------------------- wind power & PV -----------------------------
Pwind=sdpvar(T,1,'full');    %% output of wind power 
Ppv  =sdpvar(T,1,'full');    %% output of PV 

%%--------------------------- thermal unit --------------------------------
Pagg     = sdpvar(T,Ntype,'full');   %% output of thermal unit
S        = intvar(T,Ntype,'full');   %% on_off status;
Y        = binvar(T,Ntype,'full');   %% start up indicator
Z        = binvar(T,Ntype,'full');   %% shut down indicator
%%---------------------------- tie lines ----------------------------------
Ftie = sdpvar(T,Ntie,'full');        %% tie-line power flow
%% initial assign
if UseX0
    assign(Pwind, x0.Pwind);
    assign(Ppv, x0.Ppv);
    assign(Pagg, x0.Pagg);
    assign(S, x0.S);
    assign(Y, x0.Y);
    assign(Z, x0.Z);
    assign(Ftie, x0.Ftie);
end 
%% constraints
Constraint=[];
%--------------------- thermal unit constraints ------------------------
% binary & interger variable logic
Constraint=[Constraint,(-Ng.*Z(1,:) <= S(1,:)-S_t0 <= Ng.*Y(1,:)):'logical_1t0'];
for t=2:T
    Constraint=[Constraint,(-Ng.*Z(t,:) <= S(t,:)-S(t-1,:) <= Ng.*Y(t,:)):'logical_1'];
end
Constraint=[Constraint,(Y+Z <= ones(T,Ntype)):'logical_2'];
% output limit
for t = 1:T
   Constraint = [Constraint, (S(t,:).*Pmin <=...
       Pagg(t,:) <= S(t,:).*Pmax):'output limit'];
   Constraint = [Constraint, (zeros(1,Ntype) <=...
       S(t,:) <= Ng):'number limit'];
end

% minimum up/down time
for g=1:Ntype
    for t=1:TY_t0
        Constraint = [Constraint,(Y(t,g) == 0 ):'initial Y'];
    end
    for t=1:TZ_t0
        Constraint = [Constraint,(Z(t,g) == 0 ):'initial Z'];
    end
    for t = TY_t0+1:T
        tt=max(1,t-Minup(g)+1);
        Constraint = [Constraint, (sum(Y(tt:t,g))...
            <= 1):'min_up'];
    end
    for t = TZ_t0+1:T
        tt=max(1,t-Mindown(g)+1);
        Constraint = [Constraint, (sum(Z(tt:t,g))...
            <= 1):'min_down'];
    end  
end
% ramping up/down limit
Constraint=[Constraint,(-Rampdown.*S(1,:) <= Pagg(1,:)-Pagg_t0...
        <= Rampup.*S(1,:)):'ramp0'];
for t=2:T
    Constraint=[Constraint,(-Rampdown.*S(t,:) <= Pagg(t,:)-Pagg(t-1,:)...
        <= Rampup.*S(t,:)):'ramp'];
end

%------------------------------- wind power & PV ----------------------
Constraint=[Constraint,(zeros(T,1) <= Pwind <= Windmax):'wind power output limit'];
Constraint=[Constraint,(zeros(T,1) <= Ppv   <= PVmax):'wind power output limit'];

%------------------------------- Tie-line -----------------------------
for line=1:Ntie
    if Tieline(line,2)==1
        Constraint=[Constraint,(Ftie(:,line)==Ftie0(:,line)):'tie typeI'];
    elseif Tieline(line,2)==2
        for t=1:T
%             Constraint=[Constraint,(-Tieline(line,3)<=...
%                 Ftie(t,line)<=Tieline(line,3)):'tie typeII'];
            Constraint=[Constraint,(0 <= Ftie(t,line) <= 0 ):'tie typeII'];
        end
    elseif Tieline(line,2)==3
        for t=1:T
            Constraint=[Constraint,(-Tieline(line,3)<=...
                Ftie(t,line)<=Tieline(line,3)):'tie typeIII 1'];
        end
        for td=1:TD
           Constraint=[Constraint,(sum(Ftie(TDstart(td):TDstart(td+1),line))...
               ==Etie(td,line)):'tie typeIII 2'];
        end
    end
end
%------------------------------- power balance ------------------------
for t=1:T
    Constraint=[Constraint,(sum(Pagg(t,:))+Pwind(t)+Ppv(t)...
        ==Demand(t)+sum(Ftie(t,:))):'power balance'];
end
%------------------------------- spinning reserve ---------------------
% for t=1:T
%     Constraint=[Constraint,(sum(onoff(t,:).*Pmax)+Windmax(t)+PVmax(t)...
%         +sum(Tieline(:,3))>=Demand(t)+ReserveUp(t)):'up reserve'];
%     Constraint=[Constraint,(sum(onoff(t,:).*Pmin)-sum(Tieline(:,3))...
%         <=Demand(t)-ReserveDn(t)):'down reserve'];
% end
% for t=1:T
%     Constraint=[Constraint,(sum(onoff(t,:).*Pmax - Pthermal(t,:)) >= ReserveUp(t)):'up reserve'];
%     Constraint=[Constraint,(sum(onoff(t,:).*Pmin - Pthermal(t,:)) <= -ReserveDn(t)):'down reserve'];
% end

%% objective
minLang= -sum(Pwind)-sum(Ppv);
%     for la=1:Ntie
%         minLang = minLang +...
%             lamda(:,la)'*(Ftie(:,la)-Ftie_val(:,la))+...
%             Rho/2*(Ftie(:,la)-Ftie_val(:,la))'*(Ftie(:,la)-Ftie_val(:,la));                
%     end
%% solution
tic
Ops = sdpsettings('solver','gurobi','usex0',1,'verbose',1,'showprogress',0);
Ops.gurobi.MIPGap=0.0002;
%         Ops.gurobi.MIPGapAbs=1.0;
Ops.gurobi.OptimalityTol = 0.0002;
%         Ops.gurobi.FeasRelaxBigM   = 1.0e10;
Ops.gurobi.DisplayInterval = 20;
diag = optimize(Constraint,minLang,Ops); 
% check(Constraints);
if diag.problem ~= 0
    check(Constraint);
    error(yalmiperror(diag.problem));
end
toc
%% read values of variables
%%--------------------------- wind power & PV -----------------------------
out.Pwind = value(Pwind);    %% output of wind power 
out.Ppv   = value(Ppv);      %% output of PV 
%%--------------------------- thermal unit --------------------------------
out.Pagg  = value(Pagg);
out.S     = value(S);
out.Y     = value(Y);
out.Z     = value(Z);
%%---------------------------- tie lines ----------------------------------
out.Ftie  = value( Ftie);
out.minLang = value(minLang);