<?php

namespace Webkul\Sales\Repositories;

use Webkul\Core\Eloquent\Repository;

/**
 * Order Address Repository
 */
class OrderAddressRepository extends Repository
{
    /**
     * Specify Model class name
     */
    public function model(): string
    {
        return 'Webkul\Sales\Contracts\OrderAddress';
    }
}
