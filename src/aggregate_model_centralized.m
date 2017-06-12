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
% T           = in.T;                 %% time horizons
% % Nunit       = in.Nunit;             %% number of units
% Ntype       = in.Ntype;             %% number of unit type
% Ntie        = in.Ntie;              %% number of tie lines
% %%------------------------ thermal unit ---------------------------------
% Pmax        = in.Pmax;              %% unit maximum output        1xNtype
% Pmin        = in.Pmin;              %% unit minimum output        1xNtype       
% Rampup      = in.Rampup;            %% unit ramping up rates      1xNtype
% Rampdown    = in.Rampdown;          %% unit ramping down rates    1xNtype
% Minup       = in.Minup;             %% unit minimun up time       1xNtype
% Mindown     = in.Mindown;           %% unit minimum dowm time     1xNtype
% S_t0        = in.S_t0;              %% initial number being on at t=0      1xNtype
% Pagg_t0     = in.Pagg_t0;           %% initial output at t=0      1xNtype
% TY_t0       = in.TY_t0;             %% length of time Yg has to be 0 at the beginning       1xNtype
% TZ_t0       = in.TY_t0;             %% length of time Zg has to be 0 at the beginning       1xNtype
% Ng          = in.Ng;                %% number per unit type       1xNtype
% % typeID      = in.typeID;            %% type ID                    1xNunit        
% %%--------------------------  wind and PV ---------------------------------
% Windmax     = in.Windmax;           %% theory output of wind power
% PVmax       = in.PVmax;             %% theory output of PV
% %%--------------------------  tie lines -----------------------------------
% Tieline     = in.Tieline;           %% tie lines
% Ftie0       = in.Ftie0;             %% fixed power flow
% Etie        = in.Etie;              %% exchage energy each day
% TDstart     = in.TDstart;
% %%---------------------------- system -------------------------------------
% Demand      = in.Demand;            %% demand
% ReserveUp   = in.ReserveUp;         %% up reserve
% ReserveDn   = in.ReserveDn;         %% dowen reserve
% %%---------------------------- ADMM ---------------------------------------
% % Ftie_val    = in.Ftie_val;          %% exchange information of tie line power flow 
% % lamda       = in.lamda;             %% multiplers
% % Rho         = in.Rho;               %% coefficient of quadratic term
T  = in(1).T;
TD = 0;
for a=1:A
    %% variable
    %%--------------------------- wind power & PV -----------------------------
    var(a).Pwind=sdpvar(T,1,'full');    %% output of wind power 
    var(a).Ppv  =sdpvar(T,1,'full');    %% output of PV 

    %%--------------------------- thermal unit --------------------------------
    var(a).Pagg     = sdpvar(T,in(a).Ntype,'full');   %% output of thermal unit
    var(a).S        = intvar(T,in(a).Ntype,'full');   %% number of on units;
    var(a).Y        = binvar(T,in(a).Ntype,'full');   %% start up indicator
    var(a).Z        = binvar(T,in(a).Ntype,'full');   %% shut down indicator
    var(a).SY       = sdpvar(T,in(a).Ntype,'full');   %% number of startup units;
    var(a).SZ       = sdpvar(T,in(a).Ntype,'full');   %% number of shutdown units;
    %%---------------------------- tie lines ----------------------------------
    var(a).Ftie = sdpvar(T,in(a).Ntie,'full');        %% tie-line power flow
    %% initial assign
    if UseX0
        assign(var(a).Pwind, x0(a).Pwind);
        assign(var(a).Ppv, x0(a).Ppv);
        assign(var(a).Pagg, x0(a).Pagg);
        assign(var(a).S, x0(a).S);
        assign(var(a).Y, x0(a).Y);
        assign(var(a).Z, x0(a).Z);
        assign(var(a).SY, x0(a).SY);
        assign(var(a).SZ, x0(a).SZ);
        assign(var(a).Ftie, x0(a).Ftie);
    end 
end
%% constraints
Constraint=[];
for a=1:A
    %--------------------- thermal unit constraints ------------------------
    % binary & interger variable logic
    Constraint=[Constraint,( var(a).S(1,:)-in(a).S_t0 == var(a).SY(1,:) - var(a).SZ(1,:) ):'logical_1t0'];
    for t=2:T
        Constraint=[Constraint,( var(a).S(t,:)- var(a).S(t-1,:) == var(a).SY(t,:) - var(a).SZ(t,:) ):'logical_1'];
    end
    for t=1:T
        Constraint=[Constraint,( var(a).Y(t,:) <= var(a).SY(t,:) <= in(a).Ng.*var(a).Y(t,:)):'logical_2'];
        Constraint=[Constraint,( var(a).Z(t,:) <= var(a).SZ(t,:) <= in(a).Ng.*var(a).Z(t,:)):'logical_3'];
    end
    Constraint=[Constraint,(var(a).Y + var(a).Z <= ones(T,in(a).Ntype)):'logical_4'];
    % output limit
    for t = 1:T
       Constraint = [Constraint, (var(a).S(t,:).*in(a).Pmin <=...
           var(a).Pagg(t,:) <= var(a).S(t,:).*in(a).Pmax):'output limit'];
       Constraint = [Constraint, (zeros(1,in(a).Ntype) <=...
           var(a).S(t,:) <= in(a).Ng):'number limit'];
    end

    % minimum up/down time
    for g=1:in(a).Ntype
        for t=1:in(a).TY_t0
            Constraint = [Constraint,(var(a).Y(t,g) == 0 ):'initial Y'];
        end
        for t=1:in(a).TZ_t0
            Constraint = [Constraint,(var(a).Z(t,g) == 0 ):'initial Z'];
        end
        for t = in(a).TY_t0+1:T
            tt=min(T,t+in(a).Mindown(g)-1);
            Constraint = [Constraint, ((tt-t+1) - sum(var(a).Y(t:tt,g))...
                >= (tt-t+1)*var(a).Z(t,g)):'min_down'];
        end
        for t = in(a).TZ_t0+1:T
            tt=min(T,t+in(a).Minup(g)-1);
            Constraint = [Constraint, ((tt-t+1) - sum(var(a).Z(t:tt,g))...
                >= (tt-t+1)*var(a).Y(t,g)):'min_up'];
        end  
    end
    % ramping up/down limit
    Constraint=[Constraint,(-in(a).Rampdown.*var(a).S(1,:) <= var(a).Pagg(1,:)-in(a).Pagg_t0...
            <= in(a).Rampup.*var(a).S(1,:)):'ramp0'];
    for t=2:T
        Constraint=[Constraint,(-in(a).Rampdown.*var(a).S(t,:) <= var(a).Pagg(t,:)-var(a).Pagg(t-1,:)...
            <= in(a).Rampup.*var(a).S(t,:)):'ramp'];
    end

    %------------------------------- wind power & PV ----------------------
    Constraint=[Constraint,(zeros(T,1) <= var(a).Pwind <= in(a).Windmax):'wind power output limit'];
    Constraint=[Constraint,(zeros(T,1) <= var(a).Ppv   <= in(a).PVmax):'wind power output limit'];

    %------------------------------- Tie-line -----------------------------
    for line=1:in(a).Ntie
        if in(a).Tieline(line,2)==1
            Constraint=[Constraint,(var(a).Ftie(:,line)==in(a).Ftie0(:,line)):'tie typeI'];
        elseif in(a).Tieline(line,2)==2
            for t=1:T
                Constraint=[Constraint,(-in(a).Tieline(line,3)<=...
                    var(a).Ftie(t,line)<= in(a).Tieline(line,3)):'tie typeII'];
%                 Constraint=[Constraint,(0 <= var(a).Ftie(t,line) <= 0 ):'tie typeII'];
            end
        elseif in(a).Tieline(line,2)==3
            for t=1:T
                Constraint=[Constraint,(-in(a).Tieline(line,3)<=...
                    var(a).Ftie(t,line)<= in(a).Tieline(line,3)):'tie typeIII 1'];
            end
            for td=1:TD
               Constraint=[Constraint,(sum(var(a).Ftie(TDstart(td):TDstart(td+1),line))...
                   == in(a).Etie(td,line)):'tie typeIII 2'];
            end
        end
    end
    %------------------------------- power balance ------------------------
    for t=1:T
        Constraint=[Constraint,(sum(var(a).Pagg(t,:))+var(a).Pwind(t)+var(a).Ppv(t)...
            == in(a).Demand(t)+sum(var(a).Ftie(t,:))):'power balance'];
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
end
for a=1:A
    for b=a+1:A
        for la=1:in(a).Ntie
            for lb=1:in(b).Ntie
                if (in(a).Tieline(la,1)==b)&&(in(b).Tieline(lb,1)==a)
                     Constraint = [Constraint,(var(a).Ftie(:,la) == -var(b).Ftie(:,lb)):'concensus'];
                end
            end
        end
    end
end
%% objective
minLang=0;
for a=1:A
minLang= minLang-sum(var(a).Pwind)-sum(var(a).Ppv);
%     for la=1:Ntie
%         minLang = minLang +...
%             lamda(:,la)'*(Ftie(:,la)-Ftie_val(:,la))+...
%             Rho/2*(Ftie(:,la)-Ftie_val(:,la))'*(Ftie(:,la)-Ftie_val(:,la));                
%     end
end
%% solution
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
%% read values of variables
for a=1:A
    %%--------------------------- wind power & PV -----------------------------
    out(a).Pwind = value(var(a).Pwind);    %% output of wind power 
    out(a).Ppv   = value(var(a).Ppv);      %% output of PV 
    %%--------------------------- thermal unit --------------------------------
    out(a).Pagg  = value(var(a).Pagg);
    out(a).S     = value(var(a).S);
    out(a).Y     = value(var(a).Y);
    out(a).Z     = value(var(a).Z);
    out(a).SY    = value(var(a).SY);
    out(a).SZ    = value(var(a).SZ);
    %%---------------------------- tie lines ----------------------------------
    out(a).Ftie  = value( var(a).Ftie);
    out(a).minLang = value(minLang);
end