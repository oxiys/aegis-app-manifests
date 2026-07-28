import os
import time
import logging
from flask import Flask, jsonify, request
from flask_cors import CORS
import psycopg2
import psycopg2.extras

app = Flask(__name__)
CORS(app)
logging.basicConfig(level=logging.INFO)

DB_URL = os.environ.get('DATABASE_URL', 'postgresql://aegis:aegis@db:5432/aegis') # trufflehog:ignore


def get_db():
    return psycopg2.connect(DB_URL)


def init_db(retries=10, delay=3):
    """Initialize DB with retry logic to handle the race condition
    where the backend pod starts before Postgres is fully ready."""
    for attempt in range(retries):
        try:
            conn = get_db()
            cur = conn.cursor()
            cur.execute(
                '''CREATE TABLE IF NOT EXISTS todos (
                    id SERIAL PRIMARY KEY,
                    title TEXT NOT NULL,
                    completed BOOLEAN DEFAULT FALSE
                )'''
            )
            conn.commit()
            conn.close()
            logging.info('Database initialized successfully.')
            return
        except Exception as e:
            logging.warning(f'DB init attempt {attempt + 1}/{retries} failed: {e}')
            if attempt < retries - 1:
                time.sleep(delay)
    logging.error('Could not initialize database after all retries.')


@app.route('/api/health')
def health():
    return jsonify(status='ok')


@app.route('/api/ready')
def ready():
    try:
        conn = get_db()
        conn.close()
        return jsonify(status='ready')
    except Exception:
        return jsonify(status='not ready'), 503


@app.route('/api/todos', methods=['GET'])
def get_todos():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute('SELECT * FROM todos ORDER BY id')
    todos = cur.fetchall()
    conn.close()
    return jsonify(todos)


@app.route('/api/todos', methods=['POST'])
def add_todo():
    data = request.json
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute('INSERT INTO todos (title) VALUES (%s) RETURNING *', (data['title'],))
    todo = cur.fetchone()
    conn.commit()
    conn.close()
    return jsonify(todo), 201


@app.route('/api/todos/<int:todo_id>', methods=['PATCH'])
def toggle_todo(todo_id):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(
        'UPDATE todos SET completed = NOT completed WHERE id = %s RETURNING *',
        (todo_id,),
    )
    todo = cur.fetchone()
    conn.commit()
    conn.close()
    return jsonify(todo)


@app.route('/api/todos/<int:todo_id>', methods=['DELETE'])
def delete_todo(todo_id):
    conn = get_db()
    cur = conn.cursor()
    cur.execute('DELETE FROM todos WHERE id = %s', (todo_id,))
    conn.commit()
    conn.close()
    return '', 204


# Init DB at startup with retry — handles race condition with Postgres pod
init_db()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)