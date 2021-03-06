#necessary r packages
libarys = c("survival","glmnet","readxl","dplyr","doParallel","xlsx","survminer","pROC")

lapply(libarys,require,character.only = TRUE)

#loading patien data from excel
patient_data <- read_excel("~/Good/RDSmis/patient_data.xlsx") # laden der daten
#View(patient_data)

#printfunktion
#a usefull print function
printf <- function(...) invisible(print(sprintf(...)))

#set columstype from patien data str to numeric values
#colums with numeric value : Age at Diagnosis, WBC Count, Date of Diagnosis, Time to Relapse(Day), CCR (Day) 
patient_data$`Time to Relapse (Days)`<- as.numeric(patient_data$`Time to Relapse (Days)`)
patient_data$`CCR (Days)`<-as.numeric(patient_data$`CCR (Days)`)
patient_data$`Time to Relapse (Days)`[is.na(patient_data$`Time to Relapse (Days)`)]<-0
patient_data$`CCR (Days)`[is.na(patient_data$`CCR (Days)`)]<-0
patient_data$`Age at Diagnosis`<-as.numeric(patient_data$`Age at Diagnosis`)
patient_data$`WBC Count`<-as.numeric(patient_data$`WBC Count`)
#patien_data$`Date of Diagnosis`<-as.numeric(patien_data$`Date of Diagnosis`)

#new Collum "Survival Time (Day)
patient_data$`Survival Time (Day)` <- patient_data$`Time to Relapse (Days)`+patient_data$`CCR (Days)`
#fehlermeldung unknown column <- "Survival Time (Day) vorher erstellen?

#yes2 == yes
patient_data$`Relapse Status`[patient_data$`Relapse Status`=="Yes2"]<-"Yes"

#Set DDPR Status to nuermic binary values
patient_data$`DDPR Risk`[patient_data$`DDPR Risk`=="Low"]<-0
patient_data$`DDPR Risk`[patient_data$`DDPR Risk`=="High"]<-1

#reduce patien data to necessary colums
cohort=patient_data[,c(1,11,8,16,15,17)]

#divide cohort into training and validation set
training.set=cohort[which(cohort$Cohort=="Training"),1:6]
validation.set=cohort[which(cohort$Cohort=="Validation"),1:6]

#bind training and validation set to totalset
total.set=bind_rows(training.set,validation.set)


#safe triplot rds file as df. for training and validation set
#absRange Condition 1.1
df.training<-readRDS("~/Good/RDS/TriPlotData/Basal_Training_func_quadrant_absRange_condi1.1_cof0.2.rds")
df.validation<-readRDS("~/Good/RDS/TriPlotData/Basal_Validation_func_quadrant_absRange_condi1.1_cof0.2.rds")

#absRange ohne Condi 1.1
#df.training<-readRDS("~/Good/RDS/TriPlotData/Basal_Training_func_quadrant_absRange_cof0.2.rds")
#df.validation<-readRDS("~/Good/RDS/TriPlotData/Basal_Validation_func_quadrant_absRange_cof0.2.rds")

#safe rownames ("patien ID")
rownames.validation = row.names(df.validation)
rownames.training = row.names(df.training)


df.total<-bind_rows(df.training,df.validation)
sample.size=ncol(df.total)
rownames(df.total)=c(rownames.training,rownames.validation)

#View(df.total)
#total 60 patien in cohort
#no condition total 54  patient
#condition 1.1 total 41 patien

typeColNum=1

#missing patien from cohort becaus of condition 1.1
missin.patien = c(row.names(df.total),total.set$`Patient ID`)
missin.patien = names(which(table(missin.patien) == 1))

#relapsstatus in training set as numeric
condition = training.set$`Relapse Status`[which(training.set$`Patient ID`%in% row.names(df.training))]
condition[condition %in% c("Yes")]=1
condition[condition %in% c("No")]=0
condition=as.numeric(condition)

#survival time in training.set as numeric
survival=training.set$`Survival Time (Day)`[which(training.set$`Patient ID`%in%row.names(df.training))]
survival=as.numeric(survival)

#DDPR STATUS as numeric
DDPR=training.set$`DDPR Risk`[which(training.set$`Patient ID`%in%row.names(df.training))]
DDPR=as.numeric(DDPR)

#add condition/survivaltime/age to df.training
df.training=bind_cols(as.data.frame(DDPR),df.training)
names(df.training)[typeColNum] = "DDPR Status"
df.training=bind_cols(as.data.frame(condition),df.training)
names(df.training)[typeColNum]="Relaps Status"
df.training=bind_cols(as.data.frame(survival),df.training)
names(df.training)[typeColNum] = "Survivaltime (Day)"



#do same for validation set
condition = validation.set$`Relapse Status`[which(validation.set$`Patient ID`%in% row.names(df.validation))]
condition[condition %in% c("Yes")]=1
condition[condition %in% c("No")]=0
condition=as.numeric(condition)
survival = validation.set$`Survival Time (Day)`[which(validation.set$`Patient ID`%in%row.names(df.validation))]
survival = as.numeric(survival)
DDPR=validation.set$`DDPR Risk`[which(validation.set$`Patient ID`%in%row.names(df.validation))]
DDPR=as.numeric(DDPR)

df.validation=bind_cols(as.data.frame(DDPR),df.validation)
names(df.validation)[typeColNum] = "DDPR Status"
df.validation=bind_cols(as.data.frame(condition),df.validation)
names(df.validation)[typeColNum]="Relaps Status"
df.validation=bind_cols(as.data.frame(survival),df.validation)
names(df.validation)[typeColNum] = "Survivaltime (Day)"

df.training.strat = df.training
rownames(df.training.strat) = rownames.training

# glmnet need input matrix for model 
# safe df as matrix
df.training=as.matrix(df.training)
df.validation=as.matrix(df.validation)


### convert NaN/+-Inf to 0 in df.training

if (any(is.nan(df.training))) df.training[is.nan(df.training) | is.infinite(df.training)] <- -0.01
if (any(is.infinite(df.training))) df.training[is.infinite(df.training)] <- -0.01
### convert NAs to sample group mean
if (any(is.na(df.training))) {
  for ( i in 2:ncol(df.training)) {
    NA.idx = which(is.na(df.training[,i]))
    
    for (j in NA.idx) {
      tmp = df.training[which(df.training[j,1]==df.training[,1]),i]
      tmp = tmp[-which(is.na(tmp))]
      tmp = round(sample(seq(mean(tmp)-sd(tmp),mean(tmp)+sd(tmp),by=0.01),1),2)
      
      df.training[j,i] = tmp
    }
  }
}
### convert NaN/+-Inf to 0 in df.validation

if (any(is.nan(df.validation))) df.validation[is.nan(df.validation) | is.infinite(df.validation)] <- -0.01
if (any(is.infinite(df.validation))) df.validation[is.infinite(df.validation)] <- -0.01
### convert NAs to sample group mean
if (any(is.na(df.validation))) {
  for ( i in 2:ncol(df.validation)) {
    NA.idx = which(is.na(df.validation[,i]))
    
    for (j in NA.idx) {
      tmp = df.validation[which(df.validation[j,1]==df.validation[,1]),i]
      tmp = tmp[-which(is.na(tmp))]
      tmp = round(sample(seq(mean(tmp)-sd(tmp),mean(tmp)+sd(tmp),by=0.01),1),2)
      
      df.validation[j,i] = tmp
    }
  }
}


#create survival objekt(survival: Surv()) for cox model
sur_obj_validation = Surv(df.validation[,1],df.validation[,2])

#set seed for reproduction 
seed.vec = sample(10^2)
it.total = 0
cluster.size =3
all.activ.Index = all.coef.value = vector()
variabl.count = vector()
min.cvm = 100

cl <- makeCluster(cluster.size)
registerDoParallel(cl)

timeStart = Sys.time()
ptm <- proc.time()
printf("###Start %s.###",timeStart)

while (it.total < 100) {
  it.total = it.total + 1 


set.seed(seed.vec[it.total])

#set folds for cross validation manual because of imbalance data
#set folds that 1 fold contains at least 1 relaps
# result: 4 folds with 8 patients (at least 2 relaps)


#fold.id for condition 1.1
#create fold values
null.id = one.id= vector()
fold.id = rep(0,nrow(df.training))
one.id = rep(sample(1:4),3)
length(null.id)
null.id = rep(sample(1:4),5)
length(one.id)
it.set =  it.null = it.one = 1

# #fold.id for no condidion
# #create fold values
# null.id = one.id= vector()
# fold.id = rep(0,nrow(df.training))
# one.id = c(rep(sample(1:4),3),3)
# length(null.id)
# null.id = rep(sample(1:4),8)
# length(one.id)
# it.set =  it.null = it.one = 1

#create folds
while (it.set < nrow(df.training)+1){
  if (df.training[it.set,2] == 0){
      fold.id[it.set] = null.id[it.null]
      it.null = it.null+1}
  else{
    fold.id[it.set] = one.id[it.one]
    it.one = it.one +1
  }
  it.set = it.set +1
}

#create Model with cross validation
cv.fit <- cv.glmnet(df.training[,-c(1:3)],Surv(df.training[,1],df.training[,2]),
                    family = "cox",
                    alpha=1,
                    foldid = fold.id,
                    parallel= TRUE)
#plot(cv.fit)

#collect all active (!=0) coef from fited model
# lambda.min = model with min cross validation error
Coefficients<-coef(cv.fit,s=cv.fit$lambda.min)
Active.Index<-which(Coefficients!=0)
coef.value <- coef(cv.fit, s=cv.fit$lambda.min)
all.coef.value <- c(all.coef.value,coef.value)
variabl.count = c(variabl.count,length(Active.Index))
print(length(Active.Index))
tmp = min(cv.fit$cvm)

#collect best model (model with min cross validation error) 
#safe best model as op.fit
#safe active coef 
if(min.cvm > tmp){
  min.cvm = tmp
  op.fit = cv.fit
  op.variabl.count = length(Active.Index)
  op.index = Active.Index

  }
if ( it.total %% 10 == 0 ) {
  printf("At Work IT:%s ",it.total)
  print(Sys.time()-timeStart)
  print(proc.time()-ptm)
}

}
printf("End Process")
print(Sys.time()-timeStart)

stopCluster(cl)


print(table(variabl.count))
printf("Bestes Model mit:%s", op.variabl.count)

#prediction for training and validation set based on op.fit
#prediction for type cox model = relativ risk (RR)
p.training = predict(op.fit,newx = df.training[,-c(1:3)],s="lambda.min",type="response")
p.validation = predict(op.fit,newx = df.validation[,-c(1:3)],s="lambda.min",type="response")

#calculat threshold for cutoff
# "low Risk" < treshold > "high risk"
#scale RR between 0->1
scale.prediction = (p.training-min(0))/(max(p.training)-min(0))
scale.prediction[which(scale.prediction<0)] = 0 

#performance test for set of thresholds
threshold = seq(0,1,0.01)
predictions.roc = data.frame()

#safe all prediction cutoffs as df  
for (it in 1:length(threshold)){
  newline = findInterval(scale.prediction,threshold[it])
  predictions.roc = bind_cols(as.data.frame(newline),predictions.roc)
  names(predictions.roc)[1]= threshold[it]
}

#mirror df to set index right 
predictions.roc= predictions.roc[,ncol(predictions.roc):1]

#callculate error
#true prositiv = prediction 1 & relapsstatus 1
#calculate ssensitivity and false positiv rate 
all.sens = all.FP.rate = AUC = vector()
for (i in 1:length(threshold)){
  TP = length(which(predictions.roc[,i]==1 & df.training[,2]==1))
  FP = length(which(predictions.roc[,i]==1 & df.training[,2]==0))
  ALLP = length(which(df.training[,2]==1))
  ALLN = length(which(df.training[,2]==0))
  SENS = TP/ALLP
  all.sens = c(all.sens,SENS)
  FP.rate = FP/ALLN
  all.FP.rate = c(all.FP.rate,FP.rate)
  AUC = c(AUC,auc(roc(df.training[,2],predictions.roc[,i])))
}

#safe  ROC plot as pdf
pdf("Y:/AG_Baumgrass/Eric.Urbansky/Good/RDS/HIST-ROC-Plot.pdf")
par(mfrow=c(2,2),pty = "s")
#plot Roc Kurve
plot(all.FP.rate,all.sens,type = "l",ylab = "Sensitivity",xlab = "False positiv Rate", ylim = c(0,1), xlim = c(0,1),main = "ROC Kurv")

###########################################################################
# #treshold by log-rang test. find "optimal" p-value for log rang
# p.value = c()
# for(i in 1:length(names(predictions.roc))){
#   df.new = data.frame(df.training[,1],df.training[,2],predictions.roc[,i])
#   names(df.new)[1] = "TIME"
#   names(df.new)[2] = "Status"
#   names(df.new)[3] = "PREDICTION"
#   km.type=survfit(Surv(df.new$TIME,df.new$Status) ~ df.new$PREDICTION,
#                   data = df.new,
#                   type="kaplan-meier")
#   tmp = surv_pvalue(km.type, method = "1")$pval
#   p.value = c(p.value,tmp)
# }
# p.value[which(is.na(p.value)== TRUE)] = 1
# op.thresh = threshold[which(p.value == min(p.value))[1]]
##########################################################################

#finde best threshold
#fp = 0 & sens <=90
temp = which(all.sens[which(all.FP.rate == 0)]<=0.99)[1]

op.thresh = which(all.sens == all.sens[which(all.FP.rate == 0)][temp])
op.thresh = threshold[op.thresh][1]

printf("RR over %s are interpret as Status 1(Hight Risk)", op.thresh*max(p.training))
printf("RR under %s are Satus 0(Low Risk)",op.thresh*max(p.training))


#pediction RR Values aprox Relapsstaus with calculates Threshold
predicted.validation=findInterval(p.validation/max(p.training),op.thresh)
#print(predicted.validation)
predicted.training=findInterval(p.training/max(p.training),op.thresh)
#print(predicted.training)

####################################################################

#find error in Prediction.validation for DDPR
fehler.ddpr = df.validation[,2]-df.validation[,3]
fehler.ddpr[fehler.ddpr == 1]="FN"
fehler.ddpr[fehler.ddpr == -1]="FP"
fehler.ddpr[fehler.ddpr==0]=""

#find error in Prediction model
fehler.model = df.validation[,2]-predicted.validation
fehler.model[fehler.model==1]="FN"
fehler.model[fehler.model==-1]="FP"
fehler.model[fehler.model==0]=""

#compare Real Status / DDPR Status / Model Status 
vergleich.validation = data.frame(rownames.validation,df.validation[,2],df.validation[,3],fehler.ddpr,predicted.validation,fehler.model)
names(vergleich.validation)[1] = "Patien ID"
names(vergleich.validation)[2] = "Real Status"
names(vergleich.validation)[3] = "DDPR Status"
names(vergleich.validation)[4] = "Fehler DDPR"
names(vergleich.validation)[5] = "Predicted Status Model"
names(vergleich.validation)[6] = "Fehler Model"
write.xlsx(vergleich.validation, "Y:/AG_Baumgrass/Eric.Urbansky/Good/RDS/VergleichV_001.xlsx")

#find error in Prediction.training for DDPR
fehler.ddpr = df.training[,2]-df.training[,3]
fehler.ddpr[fehler.ddpr == 1]="FN"
fehler.ddpr[fehler.ddpr == -1]="FP"
fehler.ddpr[fehler.ddpr==0]=""

#find error in prediction model
fehler.model = df.training[,2]-predicted.training
fehler.model[fehler.model==1]="FN"
fehler.model[fehler.model==-1]="FP"
fehler.model[fehler.model==0]=""

#compare Real Status / DDPR Status / Model Status
vergleich.training = data.frame(rownames.training,df.training[,2],df.training[,3],fehler.ddpr,predicted.training,fehler.model)
names(vergleich.training)[1] = "Patien ID"
names(vergleich.training)[2] = "Real Status"
names(vergleich.training)[3] = "DDPR Status"
names(vergleich.training)[4] = "Fehler DDPR"
names(vergleich.training)[5] = "Predicted Status Model"
names(vergleich.training)[6] = "Fehler Model"
write.xlsx(vergleich.training, "Y:/AG_Baumgrass/Eric.Urbansky/Good/RDS/VergleichT_001.xlsx")

#bind training and validation error
vergleich.total = bind_rows(vergleich.training,vergleich.validation)
write.xlsx(vergleich.total, "Y:/AG_Baumgrass/Eric.Urbansky/Good/RDS/VergleichTotal.xlsx")

##############################################################################
#AUC
print(auc(roc(vergleich.total[,2],vergleich.total[,5])))
plot(roc(vergleich.total[,2],vergleich.total[,5]))

##############################################################################
#get active coeffizienten !!
Coef.names<-colnames(df.training[,-c(1:3)])

#get names from coef.names for all active index in op.fit
all.activ.names <- colnames(df.training[,-c(1:3)])[op.index]
all.activ.names.split <- strsplit(all.activ.names[1:length(all.activ.names)],".",fixed = TRUE)

x = vector()
y = vector()
z = vector()
modus = vector()
quat = vector()
i=0
while (i < length(all.activ.names)){
  i=i+1
  x= c(x,all.activ.names.split[[i]][1])
  y= c(y,all.activ.names.split[[i]][2])
  z= c(z,all.activ.names.split[[i]][3])
  modus= c(modus,all.activ.names.split[[i]][4])
  quat = c(quat,all.activ.names.split[[i]][5])
}

dev.off()

#safe coef names and values for op.fit as excel
df.training = as.data.frame(df.training)
df.validation = as.data.frame(df.validation)

#create heatmap for op.fit coef
df.head.training = df.training[which(colnames(df.training) %in% all.activ.names)]
df.head.validation = df.validation[which(colnames(df.validation) %in% all.activ.names)]
df.head = bind_rows(df.head.training,df.head.validation)
row.names(df.head) = c(rownames.training,rownames.validation)

#Relapsstatus as Vector Red/blue for Heatmap
relaps = as.numeric(c(df.training$`Relaps Status`,df.validation$`Relaps Status`))
relaps[relaps == 1] = "red"
relaps[relaps == 0] = "blue"

#calculate mean and var for training and validation 
all.relaps = cohort$`Patient ID`[which(cohort$`Relapse Status`== "Yes")]
all.relapsfree = cohort$`Patient ID`[which(cohort$`Relapse Status`== "No")]
all.mean.range.relaps = all.var.range.relaps = all.mean.range.relapsfree = all.var.range.relapsfree = vector()

it = 0
for (i in 1:length(names(df.head))){
  it = it +1
  all.mean.range.relaps = c(all.mean.range.relaps,mean(df.head[which(row.names(df.head) %in% all.relaps),it]))
  all.var.range.relaps = c(all.var.range.relaps,var(df.head[which(row.names(df.head) %in% all.relaps),it]))
  all.mean.range.relapsfree = c(all.mean.range.relapsfree,mean(df.head[which(row.names(df.head) %in% all.relapsfree),it]))
  all.var.range.relapsfree = c(all.var.range.relapsfree,var(df.head[which(row.names(df.head) %in% all.relapsfree),it]))
}

#safe all real absRange values 
#transponse df.head 
new.head = t(df.head)
colnames(new.head) = row.names(df.head)
row.names(new.head) = c(1:dim(new.head)[1])

#safe df as excel
all.right.index <- op.index
result.data = data.frame(all.right.index,x,y,z,modus,quat,
                         all.mean.range.relaps,all.var.range.relaps,
                         all.mean.range.relapsfree,all.var.range.relapsfree,
                         new.head)
names(result.data)[10] = "Var(AbsRange) Relapsfree"
names(result.data)[9] = "Mean(AbsRange) Relapsfree"
names(result.data)[8] = "Var(AbsRange) Relaps"
names(result.data)[7] = "Mean(AbsRange) Relaps"
names(result.data)[6] = "Quadrant"
names(result.data)[5] = "Modus"
names(result.data)[4] = "z Variable"
names(result.data)[3] = "Y Variable"
names(result.data)[2] = "x Variable"
names(result.data)[1] = "Variable Index"

write.xlsx(result.data, "Y:/AG_Baumgrass/Eric.Urbansky/Good/RDS/Variablen.xlsx")

##########################################################################

#create heatmap for all active coef.
df.training = as.data.frame(df.training)
df.validation = as.data.frame(df.validation)
df.head.training = df.training[which(colnames(df.training) %in% names(df.training[,-c(1:3)])[op.index])]
df.head.validation = df.validation[which(colnames(df.validation) %in% names(df.validation[,-c(1:3)])[op.index])]
df.head = bind_rows(df.head.training,df.head.validation)
row.names(df.head) = c(rownames.training,rownames.validation)
df.head = bind_cols(as.data.frame(relaps),df.head)
row.names(df.head) = c(rownames.training,rownames.validation)
df.head = df.head[order(df.head$relaps),]

pdf("Y:/AG_Baumgrass/Eric.Urbansky/Good/RDS/Heatmap.pdf" , width = 10)
heatmap(t(as.matrix(df.head[,-1])),scale = "none",Colv = NA, ColSideColors = relaps[order(relaps)])
dev.off()

########################################################################

#create kaplan-meier - survival Kurve
time = c(df.training[,1],df.validation[,1])
status = c(df.training[,2],df.validation[,2])
df.new = data.frame(time,status,vergleich.total[,5])
km.type=survfit(Surv(df.new[,1],df.new[,2]) ~ df.new[,3],data = df.new,type="kaplan-meier")
ggsurvplot(km.type, conf.int = TRUE, legend.labs = c("low Risk","high Risk"),ggtheme = theme_minimal(),pval = TRUE,pval.method = TRUE)
