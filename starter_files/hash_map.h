// hash_map.h -- Lab 1: Part 7.  YOU WRITE THIS FILE.
//
// What the harness and tests expect from this header:
//
//   template <typename K, typename V,
//             class Lock = std::mutex, bool Padded = true>
//       requires BasicLock<Lock>
//   class StripedHashMap;
//       explicit StripedHashMap(std::size_t nbuckets,
//                               std::size_t nstripes);
//       std::size_t bucket_count() const;
//       std::size_t stripe_count() const;
//
// satisfying ConcurrentMap<M, K, V> from interface.h.  The bucket
// count is fixed at construction: there is no resizing.  The tests
// construct one with 7 buckets and 3 stripes and fill it with
// thousands of keys, so long chains must work, just slowly.
//
// Flip HAVE_HASHED in parts.h when it compiles.

#ifndef HASH_MAP_H
#define HASH_MAP_H

#include <cstddef>
#include <functional>
#include <mutex>
#include <vector>

#include "interface.h"

template <typename K, typename V,class Lock = std::mutex, bool Padded = true> 
    requires BasicLock<Lock>
class StripedHashMap {
public:
    explicit StripedHashMap(std::size_t nbuckets, std::size_t nstripes)
        :buckets_(nbuckets), stripes_(nstripes)
    {
    };

    ~StripedHashMap(){
        for(std::size_t i = 0; i < buckets_.size(); i++){
        Node* curr = buckets_[i];
        Node* temp = nullptr;

            while(curr != nullptr){
                temp = curr->next;
                delete curr;
                curr = temp;
            }
        }
    };

    bool insert(const K& key, const V& value){
        std::size_t bucket = bucket_index(key);
        std::size_t stripe = stripe_index(bucket);
        std::lock_guard<Lock> guard(stripes_[stripe]);
        Node* curr = buckets_[bucket];

        while(curr != nullptr){
            if(curr->key == key){
                curr->value = value;
                return false;
            }
            curr = curr->next;
        }

        Node* new_node = new Node{key, value, nullptr};
        new_node->next = buckets_[bucket];
        buckets_[bucket] = new_node;
        return true;
    };

    bool find(const K& key, V& value) const{
        std::size_t bucket = bucket_index(key);
        std::size_t stripe = stripe_index(bucket);
        std::lock_guard<Lock> guard(stripes_[stripe]);
        Node* curr = buckets_[bucket];

        while(curr!=nullptr){
            if(curr->key == key){
                value = curr->value;
                return true;
            }
            curr = curr->next;
        }
        return false;
    };

    bool erase(const K& key){
        std::size_t bucket = bucket_index(key);
        std::size_t stripe = stripe_index(bucket);
        std::lock_guard<Lock> guard(stripes_[stripe]);
        Node* curr = buckets_[bucket];
        Node* prev = nullptr;
        
        while(curr!=nullptr){
            if(curr->key == key){
                if(prev == nullptr){
                    buckets_[bucket] = curr->next;
                }
                else{
                    prev->next = curr->next;
                }
                delete curr;    
                return true;
            }
            prev = curr;
            curr = curr->next;
        }
        return false;
    };

    std::size_t size() const {
        std::vector<std::unique_lock<Lock>> guards;
        guards.reserve(stripes_.size());

        for(std::size_t i = 0; i < stripes_.size(); i++){
            guards.emplace_back(stripes_[i]);
        }

        std::size_t total = 0;

        for(std::size_t i = 0; i < buckets_.size(); i++){
            Node* curr = buckets_[i];

            while(curr != nullptr){
                curr = curr->next;
                total+=1;
            }
        }
        return total;
    };

    std::size_t bucket_count() const{
        return buckets_.size();
    };

    std::size_t stripe_count() const{
        return stripes_.size();
    };

private:
    struct Node{
        K key;
        V value;
        Node* next;
    };

    std::size_t bucket_index(const K& key) const{
        return std::hash<K>{}(key) % buckets_.size();
    };

    std::size_t stripe_index(std::size_t bucket) const{
        std::size_t indexing = (buckets_.size() + stripes_.size() - 1)/ stripes_.size();
        return bucket/indexing;

    };

    std::vector<Node*> buckets_;
    mutable std::vector<Lock> stripes_;

};

#endif /* HASH_MAP_H */
