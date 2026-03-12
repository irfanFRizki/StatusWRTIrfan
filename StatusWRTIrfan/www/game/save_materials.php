<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST');
header('Access-Control-Allow-Headers: Content-Type');

$data_dir = '/root/game_data/';
$materials_file = $data_dir . 'materials.json';
$images_dir = $data_dir . 'images/';

// Buat direktori jika belum ada
if (!file_exists($data_dir)) {
    mkdir($data_dir, 0755, true);
}
if (!file_exists($images_dir)) {
    mkdir($images_dir, 0755, true);
}

// Tangani permintaan GET untuk mengambil materi
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    if (file_exists($materials_file)) {
        $materials = file_get_contents($materials_file);
        echo $materials;
    } else {
        echo json_encode([]);
    }
    exit;
}

// Tangani permintaan POST untuk menyimpan materi dan file
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Ambil data dari form
    $subject = $_POST['subject'] ?? '';
    $chapter = $_POST['chapter'] ?? '';
    $text = $_POST['text'] ?? '';
    $docx_file = $_FILES['docx'] ?? null;
    $images = $_FILES['images'] ?? [];

    // Validasi input
    if (!$subject || !$chapter) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'message' => 'Mata pelajaran dan bab wajib diisi'
        ]);
        exit;
    }

    // Muat materi yang sudah ada
    $materials = file_exists($materials_file) ? json_decode(file_get_contents($materials_file), true) : [];

    // Tangani file .docx
    $docx_path = null;
    if ($docx_file && $docx_file['type'] === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
        $docx_filename = $subject . '_bab' . $chapter . '_' . time() . '.docx';
        $docx_path = $data_dir . $docx_filename;
        if (!move_uploaded_file($docx_file['tmp_name'], $docx_path)) {
            http_response_code(500);
            echo json_encode([
                'success' => false,
                'message' => 'Gagal menyimpan file .docx'
            ]);
            exit;
        }
    }

    // Tangani file gambar
    $image_paths = [];
    if (!empty($images['name'])) {
        foreach ($images['name'] as $index => $name) {
            if ($images['type'][$index] && strpos($images['type'][$index], 'image/') === 0) {
                $image_filename = $subject . '_bab' . $chapter . '_' . time() . '_' . $index . '.' . pathinfo($name, PATHINFO_EXTENSION);
                $image_path = $images_dir . $image_filename;
                if (move_uploaded_file($images['tmp_name'][$index], $image_path)) {
                    $image_paths[] = '/game/images/' . $image_filename; // URL relatif untuk frontend
                }
            }
        }
    }

    // Perbarui materi
    if (!isset($materials[$subject])) {
        $materials[$subject] = [];
    }
    $materials[$subject][$chapter] = [
        'text' => $text,
        'docx' => $docx_path,
        'images' => $image_paths
    ];

    // Simpan ke materials.json
    if (file_put_contents($materials_file, json_encode($materials, JSON_PRETTY_PRINT))) {
        echo json_encode([
            'success' => true,
            'message' => 'Materi berhasil disimpan!',
            'path' => $materials_file
        ]);
    } else {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'message' => 'Gagal menyimpan materi'
        ]);
    }
    exit;
}

// Tangani permintaan OPTIONS untuk CORS
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

http_response_code(405);
echo json_encode([
    'success' => false,
    'message' => 'Metode tidak diizinkan'
]);
?>