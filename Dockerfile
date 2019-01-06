FROM java
ADD target/TaxiCabApplication-0.0.1-SNAPSHOT.jar /mnt/TaxiCabApplication.jar
CMD java -jar /mnt/TaxiCabApplication.jar
