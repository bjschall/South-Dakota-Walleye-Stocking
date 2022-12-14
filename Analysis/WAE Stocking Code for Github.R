library(magrittr)
library(brms)
library(Matrix)
library(tidybayes)
library(gridExtra)
library(tidyverse)

############################################################
###### Send request for access to data
wae2<-read.csv("wae2.csv",header=T)
wae3<-droplevels(filter(wae2,SpeciesStocked != "Saugeye"))

############################################################
###### Stocked vs non-stocked model
#identify priors
get_prior(CPUE_adj~Stocked + (1|Waterbody2),
          data=wae3, family=hurdle_gamma(link="log", link_hu = "logit",link_shape = "log"))

#model
stock_mod<- brm(bf(CPUE2~Stocked + (1|Waterbody2),
               hu~Stocked + (1|Waterbody2)),
            data=wae3, 
            prior = c(prior(normal(1,.5), class = "Intercept"),
                      prior(exponential(2), class="sd"),
                      prior(normal(1, .5), class = "b"),
                      prior(exponential(2), class="shape"), 
                      prior(normal(0, 2), class="b", dpar="hu")),
            family=hurdle_gamma(link="log", link_hu = "logit",link_shape = "log"),
            #sample_prior = "only",
            file="Stocked_nonstocked.rds",
            chains=4, iter=2000, cores=4)

#model summary and checks
summary(stock_mod)
bayes_R2(stock_mod)
pp_check(stock_mod)

#Sample posterior for magnitude of difference
posts.new <- add_epred_draws(stock_mod, re_formula = NA,
                             newdata = stock_mod$data %>% distinct(Stocked) %>% 
                               mutate(Waterbody2 = "NSDFNSDF"),
                             allow_new_levels = TRUE, dpar=T)

#calculate means and 95% quantile-based CrI
qi<-posts.new %>% 
  mean_qi();qi

#violin plot
posts.new %>% 
  ggplot(aes(x=factor(Stocked, level=c("Y", "N")), y=.epred))+
  # geom_point(data=wae3, aes(x=Stocked, y=CPUE2), position=position_jitter(width=0.1),alpha=0.5)+
  geom_violin(fill='gray50',trim=F)+
  ylab("Age-2 Walleye CPUE")+
  xlab(NULL)+
  scale_x_discrete(breaks=c("Y","N"),labels=c("Stocked", "Not Stocked"))+
  theme_classic()+
  #annotate("text", x=1.1, y=6, label= R^2~"= 0.218", size=6)+
  #coord_cartesian(ylim=c(0,6))+
  theme(axis.text = element_text(size=12), 
        axis.title = element_text(size=14))

#Probabilites
posts1.1<-posts.new %>%  
  ungroup() %>% 
  select(.draw, Stocked, .epred) %>% 
  pivot_wider(names_from = Stocked, values_from=.epred) %>% 
  mutate(diff=Y-N,diff2=Y-2*N, diff2.5=Y-2.5*N,diff3=Y-3*N)
sum(posts1.1$Y-posts1.1$N>0)/4000
sum(posts1.1$diff2>0)/4000
sum(posts1.1$diff2.5>0)/4000


############################################################
###### Size  of stocked products * waterbody type
#get prior 
get_prior(bf(CPUE2~Size2*Type + (1|Waterbody2),
             hu~Size2*Type + (1|Waterbody2)),
          data=wae3, family=hurdle_gamma(link="log", link_hu = "logit",link_shape = "log"))

#model
S_T<- brm(bf(CPUE2~Size2*Type + (1|Waterbody2),
            hu~Size2*Type + (1|Waterbody2)),
         data=wae3, 
         prior = c(prior(normal(1,.5), class="b"),
                   prior(normal(-1,0.5), coef="TypeMarginal"),
                   prior(exponential(2), class="sd"),
                   prior(normal(1, 0.5), class="Intercept"),
                   prior(exponential(2), class = "shape"),
                   prior(normal(0, 2), class="b", dpar="hu")),
         family=hurdle_gamma(link="log", link_hu = "logit",link_shape = "log"),
         #sample_prior = "only",
         file="Size_Type.rds", 
         chains=4, iter=2000, cores=4)

#model summary and check
summary(S_T)
bayes_R2(S_T)
pp_check(S_T)
plot(S_T)

#Sample from posterior
posts_S_T <- add_epred_draws(S_T, re_formula = NA,
                          newdata = S_T$data %>% distinct(Size2, Type) %>% 
                            mutate(Waterbody2 = "NSDFNSDF"),
                          allow_new_levels = TRUE, dpar=T)

#calculate means and 95% quantile-based CrI
qi_S_T<-posts_S_T %>% 
  mean_qi();qi3

#Estimate probabilities of differences among groups
posts_S_T_wide<-posts_S_T %>%  
  ungroup() %>% 
  select(.draw, Size2, Type, .epred) %>% 
  pivot_wider(names_from = c(Size2, Type), values_from=.epred) %>% 
  mutate(FrySF_C=d_fr_Consistent-c_sf_Consistent,
         FryLF_C=d_fr_Consistent-b_lf_Consistent,
         FryNo_C=d_fr_Consistent-a_no_Consistent,
         FrySF_M=d_fr_Marginal-c_sf_Marginal,
         FryLF_M=d_fr_Marginal-b_lf_Marginal,
         FryNo_M=d_fr_Marginal-a_no_Marginal,
         Fry_CM = d_fr_Consistent-d_fr_Marginal,
         SF_CM = c_sf_Consistent - c_sf_Marginal, 
         LF_CM = b_lf_Consistent - b_lf_Marginal,
         No_CM = a_no_Consistent - a_no_Marginal)
sum(posts_S_T_wide$FrySF_C>0)/4000
sum(posts_S_T_wide$FryLF_C>0)/4000
sum(posts_S_T_wide$FryNo_C>0)/4000
sum(posts_S_T_wide$FrySF_M>0)/4000
sum(posts_S_T_wide$FryLF_M>0)/4000
sum(posts_S_T_wide$FryNo_M>0)/4000
sum(posts_S_T_wide$Fry_CM>0)/4000
sum(posts_S_T_wide$SF_CM>0)/4000
sum(posts_S_T_wide$LF_CM>0)/4000
sum(posts_S_T_wide$No_CM>0)/4000

#Violin plot
posts_S_T %>% 
  ggplot(aes(x=factor(Size2, level=c("d_fr", "c_sf", "b_lf", "a_no")), y=.epred, fill=Type))+
  geom_violin(trim=F)+
  xlab("Size at Stocking")+ 
  ylab("Age-2 Walleye CPUE")+
  scale_x_discrete(breaks=c("a_no","b_lf","c_sf", "d_fr"),
                   labels=c("Not Stocked", "Large Fingerling", "Small Fingerling", "Fry"))+
  theme_classic()+ 
  #annotate("text", x=1.5, y=10, label= expression(R^2~"= 0.236"), size=6)+
  scale_fill_grey(start=0, end=.65)+
  ylim(c(0,15))+
  theme(axis.text = element_text(size=12), 
        axis.title = element_text(size=14))

############################################################
###### Management purpose
# model
mp<-brm(bf(CPUE2 ~ ManagementPurpose + (1|Waterbody2),
            hu ~ ManagementPurpose + (1|Waterbody2)),
         data=wae3, 
         family=hurdle_gamma(link="log", link_hu = "logit",link_shape = "log"),
         prior = c(prior(normal(0,.5), class="b"),
                   prior(exponential(0.1), class="sd"),
                   prior(normal(1, .5), class="Intercept"),
                   prior(exponential(0.5), class = "shape"), 
                   prior(normal(0,2), class="b", dpar="hu")),
         #sample_prior = "only",
         file="Management_Purpose.rds",
         chains=4, iter=2000, cores=4)

#model summary and check
summary(mp)
bayes_R2(mp)
pp_check(mp)
plot(mp)

#Sample from posterior
posts_mp <- add_epred_draws(mp, re_formula = NA,
                             newdata = mp$data %>% distinct(ManagementPurpose) %>% 
                               mutate(Waterbody2 = "NSDFNSDF"),
                             allow_new_levels = TRUE, dpar=T)

#calculate means and 95% quantile-based CrI
qi_mp<-posts_mp %>% 
  mean_qi();qi_mp

#Estimate probabilities of differences among groups
posts_mp_wide<-posts_mp %>%  
  ungroup() %>% 
  select(.draw, ManagementPurpose, .epred) %>% 
  pivot_wider(names_from = ManagementPurpose, values_from=.epred) %>% 
  mutate(SI = Supplemental - Introductory,
         SM = Supplemental - Maintenance, 
         SN = Supplemental - None, 
         IM = Introductory - Maintenance, 
         IN = Introductory - None, 
         MN = Maintenance - None)
sum(posts_mp_wide$SI>0)/4000
sum(posts_mp_wide$SM>0)/4000
sum(posts_mp_wide$SN>0)/4000
sum(posts_mp_wide$IM>0)/4000
sum(posts_mp_wide$IN>0)/4000
sum(posts_mp_wide$MN>0)/4000

#Violin plot
posts_mp %>% 
  ggplot(aes(x=factor(ManagementPurpose,level=c("Introductory", "Maintenance", "Supplemental", "None")), y=.epred))+
  geom_violin(trim=F, fill="gray50")+
  xlab("Management Purpose")+ 
  ylab("Age-2 Walleye CPUE")+
  theme_classic()+ 
  #annotate("text", x=1.5, y=10, label= expression(R^2~"= 0.236"), size=6)+
  scale_fill_grey(start=0, end=.65)+
  ylim(c(0,15))+
  theme(axis.text = element_text(size=12), 
        axis.title = element_text(size=14))

############################################################
###### Waterbody Characteristics

#model
water_mod<-brm(bf(CPUE2 ~ Hectares_std + WaterbodyType  + (1|Waterbody2),
           hu ~ Hectares_std + WaterbodyType   + (1|Waterbody2)),
        data=wae3, 
        family=hurdle_gamma(link="log", link_hu = "logit",link_shape = "log"),
        prior = c(prior(normal(0,.5), class="b"),
                  prior(exponential(0.1), class="sd"),
                  prior(normal(1, .5), class="Intercept"),
                  prior(exponential(0.5), class = "shape"), 
                  prior(normal(0,2), class="b", dpar="hu")),
        #sample_prior = "only",
        file_refit = "on_change",
        file="Waterbody_Char.rds",
        chains=4, iter=2000, cores=4)

#summary and model check
summary(water_mod)
bayes_R2(water_mod)
pp_check(water_mod)
plot(water_mod)

#sample from posterior
posts_water <- add_epred_draws(water_mod, re_formula = NA,
                                 newdata = tibble(expand.grid(Hectares_std=seq(min(wae3$Hectares_std), max(wae3$Hectares_std),length.out=100),
                                                  WaterbodyType = unique(wae3$WaterbodyType))) %>% 
                                   mutate(Waterbody2 = "NSDFNSDF"),
                                 allow_new_levels = TRUE, dpar=T)

#probability 
posts_water_wide<-posts_water %>%  
  ungroup() %>% 
  select(.draw, WaterbodyType,Hectares_std, .epred) %>% 
  pivot_wider(names_from = WaterbodyType, values_from=.epred) %>% 
  mutate(diffN_I = `Natural Basin` - `Impoundment/Excavated`)
sum(posts_water_wide$diffN_I>0)/400000

#summarize mean and 95% CrI
(water_meanqi<-posts_water %>%
  select(.draw, Hectares_std, WaterbodyType, .epred, hu) %>% 
  group_by(Hectares_std, WaterbodyType) %>% 
  mean_qi(.epred, hu))

#plot
ggplot()+
  geom_point(data=wae3, aes(x=Hectares_std, y=CPUE2), alpha=0.3)+
  geom_line(data=water_meanqi,aes(x=Hectares_std, y=.epred, col=WaterbodyType), size=1)+
  geom_ribbon(data=filter(water_meanqi, WaterbodyType=="Natural Basin"),aes(x=Hectares_std, y=.epred,ymin=.epred.lower, ymax=.epred.upper), alpha=0.4)+
  geom_ribbon(data=filter(water_meanqi, WaterbodyType=="Impoundment/Excavated"),aes(x=Hectares_std, y=.epred,ymin=.epred.lower, ymax=.epred.upper), alpha=0.4)+
  theme_classic()+
  scale_color_manual(values=c("black", "gray"))+
  xlab("Surface area (hectares)") +
  ylab("Age-2 Walleye CPGN")+
  scale_x_continuous(labels=c(0, "2,000", "4,000", "6,000", "8,000"), 
                              breaks=c(((0-mean(wae3$Hectares))/sd(wae3$Hectares)),
                                       ((2000-mean(wae3$Hectares))/sd(wae3$Hectares)),
                                       ((4000-mean(wae3$Hectares))/sd(wae3$Hectares)),
                                       ((6000-mean(wae3$Hectares))/sd(wae3$Hectares)),
                                       ((8000-mean(wae3$Hectares))/sd(wae3$Hectares))))+
  theme(axis.text = element_text(size=12), 
        axis.title = element_text(size=14), 
        legend.text = element_text(size=12))+
  ylim(0,40)

############################################################
######Environmental variables
#get prior
get_prior(bf(CPUE2~ GDD_std  + SpringPrecip_std + WSI_std + (1|Waterbody2),
             hu~Type * GDD_std + WaterbodyType + SpringPrecip_std + WSI_std + (1|Waterbody2)),
          data=wae3, family=hurdle_gamma(link="log", link_hu = "logit",link_shape = "log"))

#model
env<-brm(bf(CPUE2~ GDD_std  + SpringPrecip_std + WSI_std + (1|Waterbody2),
           hu~ GDD_std  + SpringPrecip_std + WSI_std + (1|Waterbody2)),
        data=wae3, 
        prior = c(prior(normal(1,.5), coef="WSI_std"),
                  prior(normal(1,.5), coef="GDD_std"),
                  prior(normal(1,.5), coef="SpringPrecip_std"),
                  prior(exponential(2), class="sd"),
                  prior(normal(1, 0.5), class="Intercept"),
                  prior(exponential(2), class = "shape"), 
                  prior(normal(0,2), class="b", dpar="hu")),
        family=hurdle_gamma(link="log", link_hu = "logit",link_shape = "log"),
        #sample_prior = "only",
        file="Env_mod.rds",
        chains=4, iter=2000, cores=4)

#model summary and checks
summary(env)
bayes_R2(env)
pp_check(env)
plot(env)

#Sample posterior for magnitude of difference
#Then estimate mean and 95% qi across range of values for each variable

#GDD
posts_env_GDD <- add_epred_draws(env, re_formula = NA,
                             newdata = tibble(GDD_std=seq(min(wae3$GDD_std), max(wae3$GDD_std),length.out=100),
                                              SpringPrecip_std=rep(0,100),
                                              WSI_std = rep(0,100)) %>% 
                             mutate(Waterbody2 = "NSDFNSDF"),
                             allow_new_levels = TRUE, dpar=T)

posts_env_GDD %<>%
  select(.draw, GDD_std, SpringPrecip_std, WSI_std, .epred, hu) %>% 
  group_by(GDD_std) %>% 
  mean_qi(.epred, hu)

#WSI
posts_env_WSI <- add_epred_draws(env, re_formula = NA,
                             newdata = tibble(GDD_std=rep(0,100),
                                              SpringPrecip_std=rep(0,100),
                                              WSI_std = seq(min(wae3$WSI_std), max(wae3$WSI_std),length.out=100)) %>% 
                               mutate(Waterbody2 = "NSDFNSDF"),
                             allow_new_levels = TRUE, dpar=T)
posts_env_WSI %<>%
  select(.draw, GDD_std, SpringPrecip_std, WSI_std, .epred, hu) %>% 
  group_by(WSI_std) %>% 
  mean_qi(.epred, hu)

#Spring Precip
posts_env_SP <- add_epred_draws(env, re_formula = NA,
                                 newdata = tibble(GDD_std=rep(0,100),
                                                  SpringPrecip_std=seq(min(wae3$SpringPrecip_std), max(wae3$SpringPrecip_std),length.out=100),
                                                  WSI_std = rep(0,100)) %>% 
                                   mutate(Waterbody2 = "NSDFNSDF"),
                                 allow_new_levels = TRUE, dpar=T)

posts_env_SP %<>%
  select(.draw, GDD_std, SpringPrecip_std, WSI_std, .epred, hu) %>% 
  group_by(SpringPrecip_std) %>% 
  mean_qi(.epred, hu)

#plot all three relationships and combine into one figure
(p1<-ggplot()+
  geom_point(data=wae3, aes(x=GDD_std, y=CPUE2), alpha=0.3)+
  geom_line(data=posts_env_GDD,aes(x=GDD_std, y=.epred), size=1)+
  geom_ribbon(data=posts_env_GDD,aes(x=GDD_std, y=.epred,ymin=.epred.lower, ymax=.epred.upper), alpha=0.4)+
  theme_classic()+
  xlab("Growing degree days") +
  ylab("Age-2 Walleye CPGN")+
  scale_x_continuous(labels=c("1,900", "2,100", "2,300", "2,500", "2,700", "2,900"), 
                     breaks=c(((1900-mean(wae3$GDD))/sd(wae3$GDD)),
                              ((2100-mean(wae3$GDD))/sd(wae3$GDD)),
                              ((2300-mean(wae3$GDD))/sd(wae3$GDD)),
                              ((2500-mean(wae3$GDD))/sd(wae3$GDD)),
                              ((2700-mean(wae3$GDD))/sd(wae3$GDD)),
                              ((2900-mean(wae3$GDD))/sd(wae3$GDD))),
                    limits=c(-2.35,3.4))+
  theme(axis.text = element_text(size=12), 
        axis.title = element_text(size=14))+
  ylim(0,40))

(p2<-ggplot()+
    geom_point(data=wae3, aes(x=WSI_std, y=CPUE2), alpha=0.3)+
    geom_line(data=posts_env_WSI,aes(x=WSI_std, y=.epred), size=1)+
    geom_ribbon(data=posts_env_WSI,aes(x=WSI_std, y=.epred,ymin=.epred.lower, ymax=.epred.upper), alpha=0.4)+
    theme_classic()+
    xlab("Winter severity index") +
    ylab(NULL)+
    scale_x_continuous(labels=c("-2,000", "-1,500", "-1,000", "-500"), 
                       breaks=c(((-2000-mean(wae3$WSI))/sd(wae3$WSI)),
                                ((-1500-mean(wae3$WSI))/sd(wae3$WSI)),
                                ((-1000-mean(wae3$WSI))/sd(wae3$WSI)),
                                ((-500-mean(wae3$WSI))/sd(wae3$WSI))),
                       limits=c(-2.1,2.3))+
    theme(axis.text = element_text(size=12), 
          axis.title = element_text(size=14))+
    ylim(0,40))

(p3<-ggplot()+
    geom_point(data=wae3, aes(x=SpringPrecip_std, y=CPUE2), alpha=0.3)+
    geom_line(data=posts_env_SP,aes(x=SpringPrecip_std, y=.epred), size=1)+
    geom_ribbon(data=posts_env_SP,aes(x=SpringPrecip_std, y=.epred,ymin=.epred.lower, ymax=.epred.upper), alpha=0.4)+
    theme_classic()+
    xlab("Spring precipitation (mm)") +
    ylab(NULL)+
    scale_x_continuous(labels=c("100", "200", "300", "400", "500"), 
                       breaks=c(((100-mean(wae3$SpringPrecip))/sd(wae3$SpringPrecip)),
                                ((200-mean(wae3$SpringPrecip))/sd(wae3$SpringPrecip)),
                                ((300-mean(wae3$SpringPrecip))/sd(wae3$SpringPrecip)),
                                ((400-mean(wae3$SpringPrecip))/sd(wae3$SpringPrecip)),
                                ((500-mean(wae3$SpringPrecip))/sd(wae3$SpringPrecip))),
                       limits=c(-1.5,4.15))+
    theme(axis.text = element_text(size=12), 
          axis.title = element_text(size=14))+
    ylim(0,40))

grid.arrange(p1, p2, p3, ncol=3)

#evaluate trends in hu parameter
posts_env_GDD %>% 
  ggplot(aes(x=GDD_std, y=hu))+
  geom_line()+
  geom_ribbon(aes(ymin=hu.lower, ymax=hu.upper), alpha=0.3)+
  theme_classic()

posts_env_WSI %>% 
  ggplot(aes(x=WSI_std, y=hu))+
  geom_line()+
  geom_ribbon(aes(ymin=hu.lower, ymax=hu.upper), alpha=0.3)+
  theme_classic()

posts_env_SP %>% 
  ggplot(aes(x=SpringPrecip_std, y=hu))+
  geom_line()+
  geom_ribbon(aes(ymin=hu.lower, ymax=hu.upper), alpha=0.3)+
  theme_classic()

############################################################
####### Stock-size Walleye
#filter data
adultWAE<-wae3 %>% filter(!is.na(WAE.S)) %>% 
  mutate(WAE_adj=(WAE.S-mean(WAE.S))/sd(WAE.S))

#model
wae_mod<-brm(bf(CPUE2~ WAE_adj + (1|Waterbody2),
           hu~WAE_adj + (1|Waterbody2)),
        data=adultWAE, 
        prior = c(prior(normal(0,1), class="b"),
                  prior(exponential(0.5), class="sd"),
                  prior(normal(1.5, 0.5), class="Intercept"),
                  prior(exponential(0.5), class = "shape"), 
                  prior(normal(0,2), class="b", dpar="hu")),
        family=hurdle_gamma(link="log", link_hu = "logit",link_shape = "log"),
        #sample_prior = "only",
        file="Adult_WAE.rds",
        chains=4, iter=2000, cores=4)


#model summary and checks
summary(wae_mod)
bayes_R2(wae_mod)
pp_check(wae_mod)
plot(wae_mod)

#sample posterior
posts_wae <- add_epred_draws(wae_mod, re_formula = NA,
                              newdata = tibble(WAE_adj=seq(min(adultWAE$WAE_adj), 
                                                         max(adultWAE$WAE_adj),
                                                         length.out=100)) %>% 
                                mutate(Waterbody2 = "NSDFNSDF"),
                              allow_new_levels = TRUE, dpar=T)

#summarize means and 95% CrI
wae_meanqi <- posts_wae %>%
  select(.draw, WAE_adj, .epred, hu) %>% 
  group_by(WAE_adj) %>% 
  mean_qi(.epred, hu)

#plot
ggplot()+
  geom_point(data=adultWAE, aes(x=WAE_adj, y=CPUE2), alpha=0.3)+
  geom_line(data=wae_meanqi,aes(x=WAE_adj, y=.epred), size=1)+
  geom_ribbon(data=wae_meanqi,aes(x=WAE_adj, y=.epred,ymin=.epred.lower, ymax=.epred.upper), alpha=0.4)+
  theme_classic()+
  xlab("Stock-length Walleye CPGN") +
  ylab("Age-2 Walleye CPGN")+
  scale_x_continuous(labels=c(0, 25, 50, 75, 100), 
                     breaks=c(((0-mean(adultWAE$WAE.S))/sd(adultWAE$WAE.S)),
                              ((25-mean(adultWAE$WAE.S))/sd(adultWAE$WAE.S)),
                              ((50-mean(adultWAE$WAE.S))/sd(adultWAE$WAE.S)),
                              ((75-mean(adultWAE$WAE.S))/sd(adultWAE$WAE.S)),
                              ((100-mean(adultWAE$WAE.S))/sd(adultWAE$WAE.S))))+
  theme(axis.text = element_text(size=12), 
        axis.title = element_text(size=14))+
  ylim(0,40)

############################################################
##### Centrarchids
# Filter data to only include waters with sampled centrarchids
cent<-wae3 %>% filter(!is.na(Centrarchids)) %>% 
  mutate(Centrarchids_std=(Centrarchids-mean(Centrarchids))/sd(Centrarchids))

#model
cent_mod<-brm(bf(CPUE2~ Centrarchids_std + (1|Waterbody2),
           hu~Centrarchids_std + (1|Waterbody2)),
        data=cent, 
        prior = c(prior(normal(-1,1), class="b"),
                  prior(exponential(0.5), class="sd"),
                  prior(normal(1.5, 0.5), class="Intercept"),
                  prior(exponential(0.5), class = "shape"), 
                  prior(normal(0,2), class="b", dpar="hu")),
        family=hurdle_gamma(link="log", link_hu = "logit",link_shape = "log"),
        #sample_prior = "only",
        file="Cent_mod.rds",
        chains=4, iter=2000, cores=4)

#model summary and checks
summary(cent_mod)
bayes_R2(cent_mod)
pp_check(cent_mod)
plot(cent_mod)

#Sample posterior for magnitude of difference
#GDD
posts_cent <- add_epred_draws(cent_mod, re_formula = NA,
                                 newdata = tibble(Centrarchids_std=seq(min(cent$Centrarchids_std), 
                                                                       max(cent$Centrarchids_std),
                                                                       length.out=100)) %>% 
                                   mutate(Waterbody2 = "NSDFNSDF"),
                                 allow_new_levels = TRUE, dpar=T)

#mean and 95% quantile interval
cent_meanqi <- posts_cent %>%
  select(.draw, Centrarchids_std, .epred, hu) %>% 
  group_by(Centrarchids_std) %>% 
  mean_qi(.epred, hu)

#plot
ggplot()+
  geom_point(data=cent, aes(x=Centrarchids_std, y=CPUE2), alpha=0.3)+
  geom_line(data=cent_meanqi,aes(x=Centrarchids_std, y=.epred), size=1)+
  geom_ribbon(data=cent_meanqi,aes(x=Centrarchids_std, y=.epred,ymin=.epred.lower, ymax=.epred.upper), alpha=0.4)+
  theme_classic()+
  xlab("Stock-length centrarchid CPTN") +
  ylab("Age-2 Walleye CPGN")+
  scale_x_continuous(labels=c(0,100,200,300, 400, 500), 
                     breaks=c(((0-mean(cent$Centrarchids))/sd(cent$Centrarchids)),
                              ((100-mean(cent$Centrarchids))/sd(cent$Centrarchids)),
                              ((200-mean(cent$Centrarchids))/sd(cent$Centrarchids)),
                              ((300-mean(cent$Centrarchids))/sd(cent$Centrarchids)),
                              ((400-mean(cent$Centrarchids))/sd(cent$Centrarchids)), 
                              ((500-mean(cent$Centrarchids))/sd(cent$Centrarchids))))+
  theme(axis.text = element_text(size=12), 
        axis.title = element_text(size=14))+
  ylim(0,40)

############################################################
##### Saugeye lakes
#filter data
SAE<-wae2 %>% filter(Waterbody=="Campbell"|Waterbody=="Elm"|Waterbody=="Goldsmith"|
                       Waterbody=="Mina"|Waterbody=="Richmond"|Waterbody=="White") %>% 
  mutate(SppStocked = plyr::mapvalues(SpeciesStocked, from=c("None", "Walleye", "Saugeye"), 
                                      to=c("a_none", "b_Walleye", "c_Saugeye")))

#model
sae_mod<-brm(bf(CPUE2 ~ SppStocked + (1|Waterbody2),
            hu ~ SppStocked + (1|Waterbody2)),
         data=SAE, 
         family=hurdle_gamma(link="log", link_hu = "logit",link_shape = "log"),
         prior = c(prior(normal(0.5, 0.25), class="b"),
                   prior(exponential(0.1), class="sd"),
                   prior(normal(1, .5), class="Intercept"),
                   prior(exponential(0.5), class = "shape"), 
                   prior(normal(0,2), class="b", dpar="hu")),
         #sample_prior = "only",
         file="SAE_mod.rds",
         chains=4, iter=2000, cores=4)

#model summary and checks
summary(sae_mod)
bayes_R2(sae_mod)
pp_check(sae_mod)
plot(sae_mod)

#Sample posterior for magnitude of difference
posts_sae <- add_epred_draws(sae_mod, re_formula = NA,
                              newdata = sae_mod$data %>% distinct(SppStocked) %>% 
                                mutate(Waterbody2 = "NSDFNSDF"),
                              allow_new_levels = TRUE, dpar=T)

#mean and 95% quantile interval
(sae_meanqi <- posts_sae %>%
  select(.draw, SppStocked, .epred, hu) %>% 
  group_by(SppStocked) %>% 
  mean_qi(.epred, hu))

#plot
posts_sae %>% 
  ggplot(aes(x=factor(SppStocked, level=c("c_Saugeye","b_Walleye","a_none")), y=.epred))+
  geom_violin(trim=F, fill="gray50")+
  xlab("Species Stocked")+ 
  ylab("Age-2 CPGN")+
  scale_x_discrete(breaks=c("c_Saugeye","b_Walleye","a_none"),
                   labels=c("Saugeye", "Walleye", "None"))+
  theme_classic()+ 
  #annotate("text", x=1.5, y=10, label= expression(R^2~"= 0.236"), size=6)+
  scale_fill_grey(start=0, end=.65)+
  ylim(c(0,15))+
  theme(axis.text = element_text(size=12), 
        axis.title = element_text(size=14))

#Probabilites
posts_sae2<-posts_sae %>%  
  ungroup() %>% 
  select(.draw, SppStocked, .epred) %>% 
  pivot_wider(names_from = SppStocked, values_from=.epred) %>% 
  mutate(S2W=c_Saugeye-b_Walleye, 
         S2N=c_Saugeye-a_none)
sum(posts_sae2$S2W>0)/4000
sum(posts_sae2$S2N>0)/4000

