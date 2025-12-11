<?php

declare(strict_types=1);

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Contracts\HttpClient\HttpClientInterface;

class TestController extends AbstractController {
    #[Route("/")]
    public function index(
        HttpClientInterface $client
    ): Response {
        $dead = ">>BEEF<<";
        $resp = $client->request('GET', 'https://jsonplaceholder.typicode.com/todos/1');
        return $this->render('ko.html.twig', [
            'dead' => $dead,
            'status' => $resp->getStatusCode(),
            'resp' => $resp->getContent(),
        ]);
    }
}
