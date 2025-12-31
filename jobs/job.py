# Pyspark Job for Datalake with Hadoop and Pyspark

# Imports
from pyspark.sql import SparkSession
from pyspark.ml import Pipeline
from pyspark.ml.feature import VectorAssembler, StringIndexer, OneHotEncoder
from pyspark.ml.classification import LogisticRegression
from pyspark.ml.tuning import ParamGridBuilder, CrossValidator
from pyspark.ml.evaluation import BinaryClassificationEvaluator
from pyspark.sql import Row

# Cria a sessão
spark = SparkSession.builder.appName("datalake_with_hdfs_and_spark").getOrCreate()

print("Processing started. Please wait...")

# Configura o nível de log
spark.sparkContext.setLogLevel('ERROR')

# Carrega o dataset a partir do HDFS
df_dsa = spark.read.csv("hdfs:///opt/spark/data/dataset.csv", inferSchema=True, header=False)

# Lista com os nomes das colunas
column_names = ["age", "workclass", "fnlwgt", "education", "education_num", "marital_status",
                "occupation", "relationship", "race", "sex", "capital_gain", "capital_loss",
                "hours_per_week", "native_country", "income"]

# Associa os nomes das colunas no dataframe
df_dsa = df_dsa.toDF(*column_names)

# Fill NA values with the category "Unknown" for some columns
df = df_dsa.na.fill({"workclass": "Unknown", "occupation": "Unknown", "native_country": "Unknown"})

# Drop any remaining NA values
df = df.dropna()

# List of categorical column names
categorical_columns = ["workclass", "education", "marital_status", "occupation", "relationship", "race", "sex", "native_country"]

# Create StringIndexers to convert string columns into numeric indices
indexers = [StringIndexer(inputCol=column, outputCol=column+"_index") for column in categorical_columns]

# Create One-Hot Encoders to convert indexed categorical columns into vectors
encoders = [OneHotEncoder(inputCol=column+"_index", outputCol=column+"_vec") for column in categorical_columns]

# Create a VectorAssembler to combine all feature columns into a single features vector
assembler = VectorAssembler(inputCols=[c + "_vec" for c in categorical_columns] + ["age", "fnlwgt", "education_num", "capital_gain", "capital_loss", "hours_per_week"], outputCol="features")

# Create a StringIndexer for the target column to produce numeric labels
labelIndexer = StringIndexer(inputCol="income", outputCol="label")

# Define the pipeline with all preprocessing stages
pipeline = Pipeline(stages=indexers + encoders + [assembler, labelIndexer])

# Split the dataframe into training and test sets before applying the pipeline
train_data, test_data = df.randomSplit([0.7, 0.3], seed=42)

# Fit the pipeline only on the training data
pipeline_model = pipeline.fit(train_data)

# Apply the fitted pipeline to both training and test data
train_transformed = pipeline_model.transform(train_data)
test_transformed = pipeline_model.transform(test_data)

# Create an instance of the Logistic Regression estimator
lr = LogisticRegression(featuresCol="features", labelCol="label")

# Build a parameter grid for hyperparameter tuning (regularization parameter)
lr_paramGrid = ParamGridBuilder().addGrid(lr.regParam, [0.1, 0.01]).build()

# Create an evaluator for binary classification using AUC (Area Under ROC)
evaluator = BinaryClassificationEvaluator(metricName="areaUnderROC")

# Configure CrossValidator with the estimator, parameter grid, evaluator and number of folds
cv = CrossValidator(estimator=lr,
                    estimatorParamMaps=lr_paramGrid,
                    evaluator=evaluator,
                    numFolds=5,
                    parallelism=3)

# Train the logistic regression model using cross-validation to find the best hyperparameters
cv_model = cv.fit(train_transformed)

# Apply the trained model to the test set to generate predictions
predictions = cv_model.transform(test_transformed)

# Evaluate the model performance on the test set using AUC
auc = evaluator.evaluate(predictions)

# Create a DataFrame with the AUC metric (to save to HDFS as CSV)
auc_df = spark.createDataFrame([Row(auc=auc)])

# Save the model and AUC result to HDFS
cv_model.write().overwrite().save("hdfs:///opt/spark/data/model")
auc_df.write.csv("hdfs:///opt/spark/data/auc", mode="overwrite")

print("Processing completed successfully. Thank you for using the local cluster.")
