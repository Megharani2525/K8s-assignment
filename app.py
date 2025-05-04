from flask import Flask, jsonify, request

app = Flask(__name__)

@app.route('/')
def home():
    return "Hello from Kubernetes!"

@app.route('/health')
def health():
    return jsonify(status="UP"), 200

@app.route('/hello/<name>')
def hello_name(name):
    return f"Hello, {name}!"

@app.route('/add', methods=['POST'])
def add():
    data = request.get_json()
    a = data.get('a', 0)
    b = data.get('b', 0)
    result = a + b
    return jsonify(result=result)

@app.route('/info')
def info():
    return jsonify(
        app="Flask Kubernetes App",
        version="1.0",
        author="Your Name"
    )

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
