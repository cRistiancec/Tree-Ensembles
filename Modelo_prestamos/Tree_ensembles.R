#Cargamos librerias y fijamos directorio de trabajo
library(rstudioapi)
library(dplyr)
current_path <- getActiveDocumentContext()$path 
setwd(dirname(current_path ))

#Cargamos los datos
Data<-data.table::fread("Data/loan.csv",header = TRUE, sep=",", stringsAsFactors = TRUE)

#Filtramos los datos para considerar solo los prestamos NO vigentes y los transformamos en
# una nueva variable categorica con dos  categorias 1) Pagados (Fully Paid) 2) impago (Default y Charged off)
Data<-Data %>% filter(loan_status =="Charged Off" | loan_status == "Default" | loan_status == "Fully Paid") %>%
  mutate(loan_result=ifelse(loan_status == "Fully Paid",1,0))
Data$loan_result<-factor(Data$loan_result,levels = c(1,0),labels =c("Paid","Not paid"))

#An??lisis exploratorio

  #Frequencia de cada clase
class_freq<-summary(Data$loan_result)
class_prop<-prop.table(class_freq)
saveRDS(as.data.frame(class_prop),"Class_proportions.rds")

#Modelos
  
  #Seleccionamos las variables a considerar para el modelo
Model_data<-Data %>% select(id,loan_result,loan_amnt,term,int_rate,grade,sub_grade,emp_length,home_ownership,
                            annual_inc,verification_status,pymnt_plan,purpose,zip_code,addr_state,open_acc,
                            pub_rec,total_acc,dti,delinq_2yrs,out_prncp,last_pymnt_amnt,acc_now_delinq)



  #Generamos Train y test sets
N<-nrow(Model_data)
train_size<-round(0.75*N)
test_size<-N-train_size
set.seed(123)
train_index<-sample(N,train_size)
train_set<-Model_data[train_index,]
test_set<-Model_data[-train_index,]

  #Entrenamos y evaluamos arboles individuales

    #Algoritmo CART con optimal complexity parameter pruning (rpart implementation)
CART_tree<-rpart::rpart(loan_result~.,data=train_set[,-1],method="class")
optimal_cp <- CART_tree$cptable[which.min(CART_tree$cptable[,"xerror"]),"CP"]
CART_tree<-rpart::prune(CART_tree,cp=optimal_cp)
plot(CART_tree)
text(CART_tree, use.n=TRUE, all=TRUE, cex=.8)
CART_tree_predict<-predict(CART_tree,test_set,type="class")
CART_tree_predict_probs<-predict(CART_tree,test_set)
CART_cm<-caret::confusionMatrix(CART_tree_predict,test_set$loan_result, positive="Not paid")

    #Algoritmo C5.0
C50_tree<-C50::C5.0(train_set[,3:23],train_set[,2])
C50_tree_predict<-predict(C50_tree,test_set[3:23],type = "class")
C50_cm<-caret::confusionMatrix(C50_tree_predict,test_set$loan_result, positive="Not paid")

  #Entrenamos y evaluamos los ensembles

    #Boosting utilizando el algoritmo C5.0 
iteraciones<-list(5,10,15,20,25) #definimos el numero de iteraciones
C50_boosts<-lapply(iteraciones,function(iter){return(C50::C5.0(train_set[,3:23],train_set[,2],trials=iter))})
C50_boosts_predict<-lapply(C50_boosts,function(model){return(predict(model,test_set[3:23],type = "class"))})
C50_boosts_cm<-lapply(C50_boosts_predict,function(pred){return(caret::confusionMatrix(pred,test_set$loan_result, positive="Not paid"))})
Accuracies_C50_boosts<-unlist(lapply(C50_boosts_cm,function(cm){return(cm$overall[1])}))
Kappas_C50_boosts<-unlist(lapply(C50_boosts_cm,function(cm){return(cm$overall[2])}))
Sensitivities_C50_boosts<-unlist(lapply(C50_boosts_cm,function(cm){return(cm$byClass[1])}))
Specificities_C50_boosts<-unlist(lapply(C50_boosts_cm,function(cm){return(cm$byClass[2])}))
Precisions_C50_boosts<-unlist(lapply(C50_boosts_cm,function(cm){return(cm$byClass[5])}))


    #Boosting con el algoritmo Adaboost.M1
Adaboosts<-lapply(iteraciones,function(iter){return(fastAdaboost::adaboost(loan_result~.,train_set[,-1],nIter = iter))})
Adaboosts_predict<-lapply(Adaboosts,function(model){return(predict(model,test_set[3:23]))})
Adaboosts_cm<-lapply(Adaboosts_predict,function(pred){return(caret::confusionMatrix(pred$class,test_set$loan_result, positive="Not paid"))})
Accuracies_Adaboosts<-unlist(lapply(Adaboosts_cm,function(cm){return(cm$overall[1])}))
Kappas_Adaboosts<-unlist(lapply(Adaboosts_cm,function(cm){return(cm$overall[2])}))
Sensitivities_Adaboosts<-unlist(lapply(Adaboosts_cm,function(cm){return(cm$byClass[1])}))
Specificities_Adaboosts<-unlist(lapply(Adaboosts_cm,function(cm){return(cm$byClass[2])}))
Precisions_Adaboosts<-unlist(lapply(Adaboosts_cm,function(cm){return(cm$byClass[5])}))




    #Random Forest

      #Omitimos factores de m??s de 53 niveles que no son soportados por el algoritmo
RF_train_set<-select(train_set,-id,-zip_code)
RF_test_set<-select(test_set,-id,-zip_code)

    #Entrenamos y evaluamos los random forests
n_trees<-list(100,200,300,400,500)
     #con parametro m=5
Random_forests<-lapply(n_trees,function(n){randomForest::randomForest(loan_result~.,data=RF_train_set, ntree=n, mtry=5)})
Random_forests_pred<-lapply(Random_forests, function(model){return(predict(model,RF_test_set,type="response"))})
Random_forests_cm<-lapply(Random_forests_pred,function(pred){return(caret::confusionMatrix(pred,test_set$loan_result, positive="Not paid"))})
Accuracies_RF<-unlist(lapply(Random_forests_cm,function(cm){return(cm$overall[1])}))
Kappas_RF<-unlist(lapply(Random_forests_cm,function(cm){return(cm$overall[2])}))
Sensitivities_RF<-unlist(lapply(Random_forests_cm,function(cm){return(cm$byClass[1])}))
Specificities_RF<-unlist(lapply(Random_forests_cm,function(cm){return(cm$byClass[2])}))
Precisions_RF<-unlist(lapply(Random_forests_cm,function(cm){return(cm$byClass[5])}))

#Guardamos las metricas de los ensembles
save(Accuracies_Adaboosts,Accuracies_C50_boosts,Accuracies_RF,Kappas_Adaboosts,Kappas_C50_boosts,Kappas_RF,
     Sensitivities_Adaboosts,Sensitivities_C50_boosts,Sensitivities_RF,Specificities_Adaboosts,Specificities_C50_boosts,
     Specificities_RF,Precisions_Adaboosts,Precisions_C50_boosts,Precisions_RF,file="metrics.RData")

#Guardamos los mejores modelos
Best_C50_boost<-C50_boosts[[3]]
Best_RF<-Random_forests[[2]]
Best_C50_preds<-C50_boosts_predict[[3]]
Best_RF_preds<-Random_forests_pred[[2]]
Best_C50_cm<-C50_boosts_cm[[3]]
Best_RF_cm<-Random_forests_cm[[2]]
save(Best_C50_boost,Best_RF,file="Best_ensembles.RData")
save(Best_C50_preds,Best_RF_preds,file="Best_ensembles_predictions.RData")
save(Best_C50_cm,Best_RF_cm,file="Best_ensembles_confusion_matrix.RData")

#Obtenemos ROC curves para los dos mejores modelos y las guardamos
C50_probs<-predict(Best_C50_boost,test_set[3:23],type = "prob")
C50_ROC<-pROC::roc(test_set$loan_result,C50_probs[,2])

RF_probs<-predict(Best_RF,RF_test_set,type = "prob")
RF_ROC<-pROC::roc(test_set$loan_result,RF_probs[,2])

save(C50_ROC,RF_ROC,file="ROCs.RData")
