# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function p = normpdf(x,mu,sigma)
p = 1./sqrt(2.*pi.*sigma.^2).*exp(-((x-mu).^2)./(2.*sigma.^2));
end
