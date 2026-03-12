<?php
/**
 * Script untuk membuat file-file contoh JSON di folder /root/game/
 * Jalankan script ini sekali untuk setup awal
 */

$game_folder = '/root/game/';

// Buat folder jika belum ada
if (!file_exists($game_folder)) {
    mkdir($game_folder, 0755, true);
    echo "✅ Folder $game_folder berhasil dibuat\n";
}

// Contoh soal Matematika BAB 1
$matematika_bab1 = [
    [
        "question" => "Berapa hasil dari 5 + 3?",
        "options" => [
            ["text" => "6", "letter" => "A"],
            ["text" => "7", "letter" => "B"],
            ["text" => "8", "letter" => "C"],
            ["text" => "9", "letter" => "D"]
        ],
        "correct" => 2,
        "image" => null
    ],
    [
        "question" => "Berapa hasil dari 10 - 4?",
        "options" => [
            ["text" => "5", "letter" => "A"],
            ["text" => "6", "letter" => "B"],
            ["text" => "7", "letter" => "C"],
            ["text" => "8", "letter" => "D"]
        ],
        "correct" => 1,
        "image" => null
    ],
    [
        "question" => "2 + 2 = ?",
        "options" => [
            ["text" => "3", "letter" => "A"],
            ["text" => "4", "letter" => "B"],
            ["text" => "5", "letter" => "C"],
            ["text" => "6", "letter" => "D"]
        ],
        "correct" => 1,
        "image" => null
    ],
    [
        "question" => "Berapa sisi yang dimiliki persegi?",
        "options" => [
            ["text" => "3 sisi", "letter" => "A"],
            ["text" => "4 sisi", "letter" => "B"],
            ["text" => "5 sisi", "letter" => "C"],
            ["text" => "6 sisi", "letter" => "D"]
        ],
        "correct" => 1,
        "image" => null
    ],
    [
        "question" => "1 + 1 = ?",
        "options" => [
            ["text" => "1", "letter" => "A"],
            ["text" => "2", "letter" => "B"],
            ["text" => "3", "letter" => "C"],
            ["text" => "4", "letter" => "D"]
        ],
        "correct" => 1,
        "image" => null
    ]
];

// Contoh soal Bahasa Indonesia BAB 1
$bahasa_indonesia_bab1 = [
    [
        "question" => "Huruf pertama dalam alfabet adalah?",
        "options" => [
            ["text" => "A", "letter" => "A"],
            ["text" => "B", "letter" => "B"],
            ["text" => "C", "letter" => "C"],
            ["text" => "D", "letter" => "D"]
        ],
        "correct" => 0,
        "image" => null
    ],
    [
        "question" => "Apa lawan kata dari 'besar'?",
        "options" => [
            ["text" => "Tinggi", "letter" => "A"],
            ["text" => "Kecil", "letter" => "B"],
            ["text" => "Panjang", "letter" => "C"],
            ["text" => "Lebar", "letter" => "D"]
        ],
        "correct" => 1,
        "image" => null
    ],
    [
        "question" => "Kata benda untuk tempat tinggal adalah?",
        "options" => [
            ["text" => "Makan", "letter" => "A"],
            ["text" => "Tidur", "letter" => "B"],
            ["text" => "Rumah", "letter" => "C"],
            ["text" => "Jalan", "letter" => "D"]
        ],
        "correct" => 2,
        "image" => null
    ],
    [
        "question" => "Berapa jumlah huruf vokal dalam bahasa Indonesia?",
        "options" => [
            ["text" => "4", "letter" => "A"],
            ["text" => "5", "letter" => "B"],
            ["text" => "6", "letter" => "C"],
            ["text" => "7", "letter" => "D"]
        ],
        "correct" => 1,
        "image" => null
    ],
    [
        "question" => "Apa kata sapaan untuk orang yang lebih tua?",
        "options" => [
            ["text" => "Kamu", "letter" => "A"],
            ["text" => "Bapak/Ibu", "letter" => "B"],
            ["text" => "Aku", "letter" => "C"],
            ["text" => "Dia", "letter" => "D"]
        ],
        "correct" => 1,
        "image" => null
    ]
];

// Contoh soal PJOK BAB 1
$pjok_bab1 = [
    [
        "question" => "Olahraga apa yang menggunakan bola dan dimainkan dengan kaki?",
        "options" => [
            ["text" => "Basket", "letter" => "A"],
            ["text" => "Sepak Bola", "letter" => "B"],
            ["text" => "Voli", "letter" => "C"],
            ["text" => "Tenis", "letter" => "D"]
        ],
        "correct" => 1,
        "image" => null
    ],
    [
        "question" => "Berapa jumlah pemain dalam satu tim sepak bola?",
        "options" => [
            ["text" => "9 orang", "letter" => "A"],
            ["text" => "10 orang", "letter" => "B"],
            ["text" => "11 orang", "letter" => "C"],
            ["text" => "12 orang", "letter" => "D"]
        ],
        "correct" => 2,
        "image" => null
    ],
    [
        "question" => "Apa yang harus dilakukan sebelum berolahraga?",
        "options" => [
            ["text" => "Tidur", "letter" => "A"],
            ["text" => "Pemanasan", "letter" => "B"],
            ["text" => "Makan banyak", "letter" => "C"],
            ["text" => "Bermain game", "letter" => "D"]
        ],
        "correct" => 1,
        "image" => null
    ],
    [
        "question" => "Lari termasuk olahraga untuk melatih?",
        "options" => [
            ["text" => "Otak", "letter" => "A"],
            ["text" => "Kecepatan", "letter" => "B"],
            ["text" => "Suara", "letter" => "C"],
            ["text" => "Penglihatan", "letter" => "D"]
        ],
        "correct" => 1,
        "image" => null
    ]
];

// Simpan file-file
$files = [
    'matematika_bab1.json' => $matematika_bab1,
    'bahasa_indonesia_bab1.json' => $bahasa_indonesia_bab1,
    'pjok_bab1.json' => $pjok_bab1
];

foreach ($files as $filename => $data) {
    $filepath = $game_folder . $filename;
    $json = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
    
    if (file_put_contents($filepath, $json)) {
        $count = count($data);
        echo "✅ File $filename berhasil dibuat ($count soal)\n";
    } else {
        echo "❌ Gagal membuat file $filename\n";
    }
}

echo "\n🎉 Setup selesai! File contoh sudah tersedia di $game_folder\n";
echo "\nFile yang dibuat:\n";
foreach ($files as $filename => $data) {
    echo "  - $filename (" . count($data) . " soal)\n";
}
?>