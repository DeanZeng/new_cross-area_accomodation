function [TY_t0,TZ_t0]= getTYZ_t0(Y,Z,Minup,Mindown)
[T,N]=size(Y);
TY_t0=zeros(1,N);
TZ_t0=zeros(1,N);
for i=1:N
    for t=0:Mindown(i)
        if Z(T-t,i) == 1
            break;
        end
    end
    TY_t0(i) = max(0, Mindown(i)-t-1);
end
for i=1:N
    for t=0:Minup(i)
        if Y(T-t,i) == 1
            break;
        end
    end
    TZ_t0(i) = max(0, Minup(i)-t-1);
end

