# Messaging-API
## Introduction
A fully scalable RESTful messaging api that runs on Docker written in Python using Django and Django Rest Framework with Celery for asynchronous tasking, Reddis message broker and Postgres for a DB. 

The project is implementing microservices architecture and uses thechnologies like: JWT, replication streaming, middleware and monitoring.

## Stack
Docker, NGINX, Gunicorn, Django, Django rest Framework, Celery, Celery Flower, Redis, Postgres, PGPool, PGAdmin and DJDT.

## Technologies used
• NGINX- Used as a webserver.

• Gunicorn- uesd as web service gateway interface. 

• Microservices- The project has two services one handle authentication requsts and the other for messages read and write requests.

• SimpleJWT- The requests that are sent to the server are authenticated by with both access token and refresh token to ensure fraud and identity theft. The access token is given to the user when he logs in it has an expiration time of an 5 minutes the user gets it in the response or when he request to refresh it when it is expired.
The refresh token is also given when the user logs in and it is stored in the cookies as an HttpOnly so the refresh token only visible to the server.

• Postgres- Created two Postgres databases for scalability purposes synchronized with steaming replication. the main handle both read and write requests and the salve handle onlt read requests. The databases handle all conversations,messages and users data using Django bulit-in user system and custom models. Optinized queries using select_related to minimize the amout of SQL queries needed for a singke action.   

• PGPool- Serves as a load balncer between the two Postgres databases and routes the request dependig one the operation (write operation to main and read operation to both main and slave).

• PGAdmin- Used to monitor and manage Postgres datadases.

• DJDT- Used to optimize requests queries and maximize response time of requests. 

• Middleware- Middleware was used to insure tokens validation before executing requests.

• Celery- Creatad Celery worker to make the API requests and resppnse work Asynchronous.

• Celery Flower- Monitors the Celery worker and tasks.

• Redis- Used as Celery Broker to store results from tasks.


## API requests

• Write Message- Sends a message to specified user.

• Read Message- Read the last message from a specied user.

• Delete Message- Deletes a nessage from the users conversations.

• Get All Messages- Get all messages from specied user.

• Get Unread Messages-Get all unread messages from specied user.

• Authentication- Authenticate username and password and returns access token and refresh token.

• Register- Signs a new user to the system.

• Token- Refresh a new access token.



